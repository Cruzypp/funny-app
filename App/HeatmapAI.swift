import Accelerate
import CoreLocation
import CoreML
import FirebaseCore
import Foundation
import Observation
import SwiftUI

struct HeatZone: Identifiable {
    var id: String
    var center: CLLocationCoordinate2D
    var radius: CLLocationDistance
    var level: SafetyLevel
    var opacity: Double
    var title: String
    var detail: String
    var riskScore: Double
    var signalCount: Int
    var transportType: String

    var color: Color {
        switch level {
        case .high: T.safe
        case .medium: T.warn
        case .low: T.risk
        }
    }

    var scoreLabel: String {
        "\(Int((riskScore * 100).rounded()))%"
    }
}

@MainActor
@Observable
final class HeatmapStore {
    private let service: FirebaseService
    private let builder = HeatmapZoneBuilder()

    private(set) var snapshot: FSHeatmapSnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    var signalCount: Int {
        snapshot.reports.count + snapshot.incidents.count + snapshot.segments.reduce(0) { $0 + $1.reportsCount }
    }

    init(service: FirebaseService? = nil) {
        self.service = service ?? FirebaseService.shared
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let data = await service.fetchHeatmapSnapshot()
        snapshot = data
        lastUpdated = Date()
        errorMessage = data.reports.isEmpty && data.segments.isEmpty && data.incidents.isEmpty
            ? "No hay datos de seguridad todavía."
            : nil
    }

    func zones(timeFilter: TimeFilter, modeFilter: ModeFilter) -> [HeatZone] {
        builder.zones(snapshot: snapshot, timeFilter: timeFilter, modeFilter: modeFilter)
    }

    func topZone(timeFilter: TimeFilter, modeFilter: ModeFilter) -> HeatZone? {
        zones(timeFilter: timeFilter, modeFilter: modeFilter).first
    }
}

private struct HeatmapZoneBuilder {
    private let predictor = HeatmapRiskPredictor()

    func zones(snapshot: FSHeatmapSnapshot, timeFilter: TimeFilter, modeFilter: ModeFilter) -> [HeatZone] {
        let stationLookup = snapshot.stations.reduce(into: [String: FSStation]()) { result, station in
            result[station.name.heatmapKey] = result[station.name.heatmapKey] ?? station
        }

        var zones = snapshot.segments.compactMap { segment -> HeatZone? in
            guard modeFilter.matches(transportType: segment.transportType) else { return nil }
            guard let coordinate = coordinate(for: segment, stationsByName: stationLookup) else { return nil }

            let reports = snapshot.reports.filter { report in
                report.segmentId.heatmapKey == segment.id.heatmapKey &&
                timeFilter.contains(hour: report.hour) &&
                modeFilter.matches(transportType: report.transportType)
            }

            let incidentRisk = nearbyIncidentRisk(
                incidents: snapshot.incidents,
                coordinate: coordinate,
                timeFilter: timeFilter
            )

            let prediction = predictor.predict(
                segment: segment,
                reports: reports,
                incidentRisk: incidentRisk,
                timeFilter: timeFilter
            )

            let signals = max(segment.reportsCount, reports.count) + Int((incidentRisk.countWeight * 8).rounded())
            let radius = 180 + min(780, sqrt(Double(max(signals, 1))) * 74)

            return HeatZone(
                id: "segment-\(segment.id)-\(timeFilter.rawValue)-\(modeFilter.rawValue)",
                center: coordinate,
                radius: radius,
                level: safetyLevel(forRisk: prediction.score),
                opacity: opacity(forRisk: prediction.score),
                title: segment.title,
                detail: "\(signals) señales - \(segment.line) - \(segment.transportType)",
                riskScore: prediction.score,
                signalCount: signals,
                transportType: segment.transportType
            )
        }

        zones.append(contentsOf: incidentZones(
            incidents: snapshot.incidents,
            timeFilter: timeFilter,
            modeFilter: modeFilter
        ))

        return zones
            .sorted { first, second in
                if first.level != second.level { return first.riskScore > second.riskScore }
                return first.signalCount > second.signalCount
            }
            .prefix(36)
            .map { $0 }
    }

    private func coordinate(for segment: FSSegment, stationsByName: [String: FSStation]) -> CLLocationCoordinate2D? {
        let from = stationsByName[segment.from.heatmapKey]
        let to = stationsByName[segment.to.heatmapKey]

        switch (from, to) {
        case let (.some(a), .some(b)):
            return CLLocationCoordinate2D(
                latitude: (a.lat + b.lat) / 2,
                longitude: (a.lng + b.lng) / 2
            )
        case let (.some(station), nil), let (nil, .some(station)):
            return station.coordinate
        default:
            return nil
        }
    }

    private func nearbyIncidentRisk(
        incidents: [FSIncident],
        coordinate: CLLocationCoordinate2D,
        timeFilter: TimeFilter
    ) -> (score: Double, countWeight: Double) {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearby = incidents.filter { incident in
            guard timeFilter.contains(date: incident.hora.dateValue()) else { return false }
            let location = CLLocation(latitude: incident.latitud, longitude: incident.longitud)
            return origin.distance(from: location) <= 850
        }

        guard !nearby.isEmpty else { return (0, 0) }

        let weightedSeverity = nearby.reduce(0.0) { total, incident in
            total + severity(for: incident.tipo) * (Double(incident.confiabilidad) / 5)
        }
        let score = min(1, weightedSeverity / max(4, Double(nearby.count) * 2.6))
        let countWeight = min(1, Double(nearby.count) / 10)
        return (score, countWeight)
    }

    private func incidentZones(
        incidents: [FSIncident],
        timeFilter: TimeFilter,
        modeFilter: ModeFilter
    ) -> [HeatZone] {
        guard modeFilter == .all || modeFilter == .walk else { return [] }

        let filtered = incidents.filter { timeFilter.contains(date: $0.hora.dateValue()) }
        let clusters = Dictionary(grouping: filtered) { incident in
            "\(Int((incident.latitud * 180).rounded())):\(Int((incident.longitud * 180).rounded()))"
        }

        return clusters.compactMap { key, incidents -> HeatZone? in
            guard !incidents.isEmpty else { return nil }

            let weightSum = incidents.reduce(0.0) { $0 + max(1, Double($1.confiabilidad)) }
            let lat = incidents.reduce(0.0) { $0 + $1.latitud * max(1, Double($1.confiabilidad)) } / weightSum
            let lng = incidents.reduce(0.0) { $0 + $1.longitud * max(1, Double($1.confiabilidad)) } / weightSum
            let severitySum = incidents.reduce(0.0) { $0 + severity(for: $1.tipo) }
            let risk = min(1, (severitySum / Double(incidents.count)) * 0.72 + min(0.28, Double(incidents.count) * 0.035))
            let radius = 190 + min(680, sqrt(Double(incidents.count)) * 92)

            return HeatZone(
                id: "incident-\(key)-\(timeFilter.rawValue)",
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: radius,
                level: safetyLevel(forRisk: risk),
                opacity: opacity(forRisk: risk),
                title: dominantIncidentTitle(incidents),
                detail: "\(incidents.count) incidentes recientes - comunidad",
                riskScore: risk,
                signalCount: incidents.count,
                transportType: "walk"
            )
        }
    }

    private func dominantIncidentTitle(_ incidents: [FSIncident]) -> String {
        let grouped = Dictionary(grouping: incidents, by: \.tipo)
        let dominant = grouped.max { $0.value.count < $1.value.count }?.key

        switch dominant {
        case .robo:
            return "Reportes de robo"
        case .acoso:
            return "Reportes de acoso"
        case .zonaOscura:
            return "Zona con poca luz"
        case .accidente:
            return "Accidentes reportados"
        case .otro:
            return "Reportes comunitarios"
        case nil:
            return "Reportes comunitarios"
        }
    }

    private func severity(for type: TipoIncidente) -> Double {
        switch type {
        case .robo: 0.95
        case .acoso: 0.88
        case .zonaOscura: 0.58
        case .accidente: 0.72
        case .otro: 0.48
        }
    }

    private func safetyLevel(forRisk risk: Double) -> SafetyLevel {
        switch risk {
        case ..<0.34: .high
        case ..<0.66: .medium
        default: .low
        }
    }

    private func opacity(forRisk risk: Double) -> Double {
        min(0.52, max(0.24, 0.24 + risk * 0.32))
    }
}

private struct HeatmapRiskPredictor {
    private let model: MLModel?

    init() {
        let modelURL = Bundle.main.url(forResource: "SafetyHeatmapRegressor", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "SafetyZoneRegressor", withExtension: "mlmodelc")

        if let modelURL {
            model = try? MLModel(contentsOf: modelURL)
        } else {
            model = nil
        }
    }

    func predict(
        segment: FSSegment,
        reports: [FSReport],
        incidentRisk: (score: Double, countWeight: Double),
        timeFilter: TimeFilter
    ) -> (score: Double, confidence: Double) {
        let averageSafety = reports.mean(\.safety) ?? (5 - segment.riskScore * 4)
        let averageLighting = reports.mean(\.lighting) ?? averageSafety
        let averageCrowd = reports.mean(\.crowd) ?? 3
        let reportRisk = clamp(1 - ((averageSafety - 1) / 4))
        let lightingRisk = clamp(1 - ((averageLighting - 1) / 4))
        let crowdRisk = clamp(1 - ((averageCrowd - 1) / 4))
        let segmentRisk = clamp(segment.riskScore)
        let timeRisk = timeFilter.riskPrior
        let transport = segment.transportType.normalizedTransportMode
        let signalCount = Double(max(reports.count, segment.reportsCount))
        let features = [
            reportRisk,
            lightingRisk,
            crowdRisk,
            segmentRisk,
            incidentRisk.score,
            timeRisk,
        ]

        let score = modelScore(
            features: features,
            signalCount: signalCount,
            transport: transport,
            timeFilter: timeFilter
        ) ?? fallbackScore(features)

        let confidence = min(1, (signalCount + incidentRisk.countWeight * 10) / 16)
        let blended = score * (0.72 + confidence * 0.18) + segmentRisk * (0.28 - confidence * 0.18)
        return (clamp(blended), confidence)
    }

    private func modelScore(
        features: [Double],
        signalCount: Double,
        transport: String,
        timeFilter: TimeFilter
    ) -> Double? {
        guard let model else { return nil }

        let input: [String: MLFeatureValue] = [
            "reported_risk": MLFeatureValue(double: features[0]),
            "lighting_risk": MLFeatureValue(double: features[1]),
            "crowd_risk": MLFeatureValue(double: features[2]),
            "segment_risk": MLFeatureValue(double: features[3]),
            "incident_risk": MLFeatureValue(double: features[4]),
            "time_risk": MLFeatureValue(double: features[5]),
            "reports_count": MLFeatureValue(double: signalCount),
            "transport_walk": MLFeatureValue(double: transport == "walk" ? 1 : 0),
            "transport_metro": MLFeatureValue(double: transport == "metro" ? 1 : 0),
            "transport_bus": MLFeatureValue(double: transport == "bus" ? 1 : 0),
            "hour": MLFeatureValue(double: Double(timeFilter.representativeHour)),
        ]

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: input)
            let output = try model.prediction(from: provider)

            if let value = output.featureValue(for: "risk_score")?.doubleValue {
                return clamp(value)
            }

            for name in output.featureNames {
                if let value = output.featureValue(for: name), value.type == .double {
                    return clamp(value.doubleValue)
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func fallbackScore(_ features: [Double]) -> Double {
        let weights = [0.34, 0.16, 0.10, 0.20, 0.14, 0.06]
        var score = 0.0
        vDSP_dotprD(features, 1, weights, 1, &score, vDSP_Length(weights.count))
        return clamp(score)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private extension Array where Element == FSReport {
    func mean(_ keyPath: KeyPath<FSReport, Double>) -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1[keyPath: keyPath] } / Double(count)
    }
}

extension TimeFilter {
    var representativeHour: Int {
        switch self {
        case .morning: 8
        case .afternoon: 16
        case .night: 22
        }
    }

    var riskPrior: Double {
        switch self {
        case .morning: 0.22
        case .afternoon: 0.34
        case .night: 0.82
        }
    }

    func contains(hour: Int) -> Bool {
        let normalized = (hour % 24 + 24) % 24
        switch self {
        case .morning:
            return (6..<12).contains(normalized)
        case .afternoon:
            return (12..<19).contains(normalized)
        case .night:
            return normalized >= 19 || normalized < 6
        }
    }

    func contains(date: Date) -> Bool {
        contains(hour: Calendar.current.component(.hour, from: date))
    }
}

extension ModeFilter {
    func matches(transportType: String) -> Bool {
        self == .all || transportType.normalizedTransportMode == rawValue
    }
}

private extension String {
    var heatmapKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    var normalizedTransportMode: String {
        let value = heatmapKey
        if value.contains("metro") || value.contains("tram") { return "metro" }
        if value.contains("bus") || value.contains("metrobus") { return "bus" }
        if value.contains("walk") || value.contains("caminar") || value.contains("pie") { return "walk" }
        return value
    }
}
