import Accelerate
import CoreLocation
import CoreML
import FirebaseFirestore
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
    private let service: FirebaseService?
    private let builder = HeatmapZoneBuilder()

    private(set) var snapshot: FSHeatmapSnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    var signalCount: Int {
        snapshot.reports.count + snapshot.incidents.count
    }

    var sourceLabel: String {
        HeatmapRiskPredictor.hasBundledModel ? "Core ML" : "Accelerate"
    }

    init(service: FirebaseService? = nil) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.service = service
        } else {
            self.service = service ?? FirebaseService.shared
        }
    }

    func load() async {
        guard !isLoading else { return }
        guard let service else {
            errorMessage = "Vista previa sin Firebase."
            return
        }

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
    private let reportClusterSpan = 0.0048

    func zones(snapshot: FSHeatmapSnapshot, timeFilter: TimeFilter, modeFilter: ModeFilter) -> [HeatZone] {
        let stationsByKey = snapshot.stations.reduce(into: [String: FSStation]()) { result, station in
            result[stationKey(line: station.line, name: station.name)] = result[stationKey(line: station.line, name: station.name)] ?? station
            result[station.name.heatmapKey] = result[station.name.heatmapKey] ?? station
            result[station.id.heatmapKey] = result[station.id.heatmapKey] ?? station
        }
        let reportSegmentKeys = Set(snapshot.reports.compactMap { report -> String? in
            guard timeFilter.contains(hour: report.hour),
                  modeFilter.matches(transportType: report.transportType) else { return nil }
            return TransitStationCatalog.canonicalSegmentKey(segmentId: report.segmentId)
        })

        var zones = snapshot.segments.compactMap { segment -> HeatZone? in
            guard modeFilter.matches(transportType: segment.transportType) else { return nil }
            guard !reportSegmentKeys.contains(TransitStationCatalog.canonicalSegmentKey(line: segment.line, from: segment.from, to: segment.to)) else { return nil }
            guard let coordinate = coordinate(for: segment, stationsByKey: stationsByKey) else { return nil }

            let matchingReports = snapshot.reports.filter { report in
                report.segmentId.heatmapKey == segment.id.heatmapKey &&
                timeFilter.contains(hour: report.hour) &&
                modeFilter.matches(transportType: report.transportType)
            }

            let fallbackReports = matchingReports.isEmpty ? snapshot.reports.filter {
                $0.segmentId.heatmapKey == segment.id.heatmapKey &&
                modeFilter.matches(transportType: $0.transportType)
            } : matchingReports

            let incidentRisk = nearbyIncidentRisk(
                incidents: snapshot.incidents,
                coordinate: coordinate,
                timeFilter: timeFilter
            )

            let prediction = predictor.predict(
                segment: segment,
                reports: fallbackReports,
                incidentRisk: incidentRisk,
                timeFilter: timeFilter
            )

            let signals = max(segment.reportsCount, fallbackReports.count) + Int((incidentRisk.countWeight * 8).rounded())
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

        zones.append(contentsOf: inferredReportSegmentZones(
            reports: snapshot.reports,
            incidents: snapshot.incidents,
            stationsByKey: stationsByKey,
            timeFilter: timeFilter,
            modeFilter: modeFilter
        ))

        zones.append(contentsOf: reportZones(
            reports: snapshot.reports,
            incidents: snapshot.incidents,
            timeFilter: timeFilter,
            modeFilter: modeFilter
        ))

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
    }

    private func coordinate(for segment: FSSegment, stationsByKey: [String: FSStation]) -> CLLocationCoordinate2D? {
        if let coordinate = segment.coordinate {
            return coordinate
        }

        let fromCoordinate = coordinate(line: segment.line, stationName: segment.from, stationsByKey: stationsByKey)
        let toCoordinate = coordinate(line: segment.line, stationName: segment.to, stationsByKey: stationsByKey)

        switch (fromCoordinate, toCoordinate) {
        case let (.some(a), .some(b)):
            return CLLocationCoordinate2D(
                latitude: (a.latitude + b.latitude) / 2,
                longitude: (a.longitude + b.longitude) / 2
            )
        case let (.some(coordinate), nil), let (nil, .some(coordinate)):
            return coordinate
        default:
            return nil
        }
    }

    private func coordinate(
        line: String,
        stationName: String,
        stationsByKey: [String: FSStation]
    ) -> CLLocationCoordinate2D? {
        stationsByKey[stationKey(line: line, name: stationName)]?.coordinate
            ?? stationsByKey[stationName.heatmapKey]?.coordinate
            ?? TransitStationCatalog.coordinate(line: line, stationName: stationName)
    }

    private func stationKey(line: String, name: String) -> String {
        "\(line.heatmapKey):\(name.heatmapKey)"
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

    private func inferredReportSegmentZones(
        reports: [FSReport],
        incidents: [FSIncident],
        stationsByKey: [String: FSStation],
        timeFilter: TimeFilter,
        modeFilter: ModeFilter
    ) -> [HeatZone] {
        let filtered = reports.filter { report in
            !report.segmentId.isEmpty &&
            timeFilter.contains(hour: report.hour) &&
            modeFilter.matches(transportType: report.transportType)
        }
        let grouped = Dictionary(grouping: filtered) { report in
            TransitStationCatalog.canonicalSegmentKey(segmentId: report.segmentId) ?? report.segmentId.heatmapKey
        }

        return grouped.compactMap { _, reports -> HeatZone? in
            guard let first = reports.first,
                  let segment = TransitStationCatalog.segmentInfo(segmentId: first.segmentId) else { return nil }

            let fromCoordinate = coordinate(line: segment.line, stationName: segment.from, stationsByKey: stationsByKey)
            let toCoordinate = coordinate(line: segment.line, stationName: segment.to, stationsByKey: stationsByKey)
            guard let coordinate = midpoint(fromCoordinate, toCoordinate) else { return nil }

            let transport = dominantTransport(in: reports)
            let incidentRisk = nearbyIncidentRisk(
                incidents: incidents,
                coordinate: coordinate,
                timeFilter: timeFilter
            )
            let prediction = predictor.predict(
                reports: reports,
                incidentRisk: incidentRisk,
                timeFilter: timeFilter,
                transportType: transport
            )
            let signals = reports.count + Int((incidentRisk.countWeight * 8).rounded())
            let radius = 150 + min(620, sqrt(Double(max(signals, 1))) * 64)

            return HeatZone(
                id: "report-segment-\(segment.key)-\(timeFilter.rawValue)-\(modeFilter.rawValue)",
                center: coordinate,
                radius: radius,
                level: safetyLevel(forRisk: prediction.score),
                opacity: opacity(forRisk: prediction.score),
                title: "\(segment.from) - \(segment.to)",
                detail: "\(signals) reportes - \(segment.line) - \(transport)",
                riskScore: prediction.score,
                signalCount: signals,
                transportType: transport
            )
        }
    }

    private func midpoint(
        _ first: CLLocationCoordinate2D?,
        _ second: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        switch (first, second) {
        case let (.some(a), .some(b)):
            return CLLocationCoordinate2D(
                latitude: (a.latitude + b.latitude) / 2,
                longitude: (a.longitude + b.longitude) / 2
            )
        case let (.some(coordinate), nil), let (nil, .some(coordinate)):
            return coordinate
        default:
            return nil
        }
    }

    private func reportZones(
        reports: [FSReport],
        incidents: [FSIncident],
        timeFilter: TimeFilter,
        modeFilter: ModeFilter
    ) -> [HeatZone] {
        let filtered = reports.filter { report in
            report.coordinate != nil &&
            timeFilter.contains(hour: report.hour) &&
            modeFilter.matches(transportType: report.transportType)
        }

        let clusters = Dictionary(grouping: filtered) { report in
            guard let coordinate = report.coordinate else { return "unmapped" }
            let latBucket = Int((coordinate.latitude / reportClusterSpan).rounded(.toNearestOrAwayFromZero))
            let lngBucket = Int((coordinate.longitude / reportClusterSpan).rounded(.toNearestOrAwayFromZero))
            return "\(latBucket):\(lngBucket)"
        }

        return clusters.compactMap { key, reports -> HeatZone? in
            let coordinates = reports.compactMap(\.coordinate)
            guard !coordinates.isEmpty else { return nil }

            let lat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
            let lng = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let transport = dominantTransport(in: reports)
            let incidentRisk = nearbyIncidentRisk(
                incidents: incidents,
                coordinate: coordinate,
                timeFilter: timeFilter
            )

            let prediction = predictor.predict(
                reports: reports,
                incidentRisk: incidentRisk,
                timeFilter: timeFilter,
                transportType: transport
            )

            let signals = reports.count + Int((incidentRisk.countWeight * 8).rounded())
            let radius = 130 + min(560, sqrt(Double(max(signals, 1))) * 58)

            return HeatZone(
                id: "report-\(key)-\(timeFilter.rawValue)-\(modeFilter.rawValue)",
                center: coordinate,
                radius: radius,
                level: safetyLevel(forRisk: prediction.score),
                opacity: opacity(forRisk: prediction.score),
                title: reportZoneTitle(reports: reports, transport: transport),
                detail: "\(signals) señales - reportes geolocalizados - \(transport)",
                riskScore: prediction.score,
                signalCount: signals,
                transportType: transport
            )
        }
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

    private func reportZoneTitle(reports: [FSReport], transport: String) -> String {
        if let segmentId = reports
            .map(\.segmentId)
            .first(where: { !$0.isEmpty }) {
            return "Reportes cerca de \(segmentId)"
        }

        switch transport.normalizedTransportMode {
        case "walk":
            return "Reportes peatonales"
        case "bus":
            return "Reportes en bus"
        case "metro":
            return "Reportes en metro"
        default:
            return "Reportes comunitarios"
        }
    }

    private func dominantTransport(in reports: [FSReport]) -> String {
        let grouped = Dictionary(grouping: reports) { $0.transportType.normalizedTransportMode }
        return grouped.max { $0.value.count < $1.value.count }?.key ?? "metro"
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
    private static let bundledModel = try? RegresionSeguridad_1(configuration: MLModelConfiguration()).model

    static var hasBundledModel: Bool {
        bundledModel != nil
    }

    init() {
        model = Self.bundledModel
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

        let reportRisk = clamp01(1 - ((averageSafety - 1) / 4))
        let lightingScore = clampToFive(averageLighting)
        let crowdScore = clampToFive(averageCrowd)
        let segmentRisk = clamp01(segment.riskScore)
        let timeRisk = timeFilter.riskPrior
        let transport = segment.transportType.normalizedTransportMode
        let signalCount = Double(max(reports.count, segment.reportsCount))

        let rawModelScore = modelScore(
            crowd: crowdScore,
            hour: timeFilter.representativeHour,
            lighting: lightingScore,
            transport: transport
        )

        let mlRisk = rawModelScore.map(normalizeModelOutput(_:)) ?? fallbackScore(
            crowd: crowdScore,
            lighting: lightingScore,
            hour: timeFilter.representativeHour,
            transport: transport
        )

        let confidence = min(1, (signalCount + incidentRisk.countWeight * 10) / 16)

        let blended =
            (mlRisk * 0.52) +
            (reportRisk * 0.18) +
            (segmentRisk * 0.16) +
            (incidentRisk.score * 0.10) +
            (timeRisk * 0.04)

        let confidenceAdjusted = blended * (0.78 + confidence * 0.14) + segmentRisk * (0.22 - confidence * 0.14)
        return (clamp01(confidenceAdjusted), confidence)
    }

    func predict(
        reports: [FSReport],
        incidentRisk: (score: Double, countWeight: Double),
        timeFilter: TimeFilter,
        transportType: String
    ) -> (score: Double, confidence: Double) {
        let averageSafety = reports.mean(\.safety) ?? 3
        let averageLighting = reports.mean(\.lighting) ?? averageSafety
        let averageCrowd = reports.mean(\.crowd) ?? 3
        let hour = reports.representativeHour ?? timeFilter.representativeHour
        let transport = transportType.normalizedTransportMode

        let reportRisk = clamp01(1 - ((averageSafety - 1) / 4))
        let lightingScore = clampToFive(averageLighting)
        let crowdScore = clampToFive(averageCrowd)
        let timeRisk = timeFilter.riskPrior

        let rawModelScore = modelScore(
            crowd: crowdScore,
            hour: hour,
            lighting: lightingScore,
            transport: transport
        )

        let mlRisk = rawModelScore.map(normalizeModelOutput(_:)) ?? fallbackScore(
            crowd: crowdScore,
            lighting: lightingScore,
            hour: hour,
            transport: transport
        )

        let confidence = min(1, (Double(reports.count) + incidentRisk.countWeight * 10) / 16)
        let blended =
            (mlRisk * 0.62) +
            (reportRisk * 0.20) +
            (incidentRisk.score * 0.14) +
            (timeRisk * 0.04)

        return (clamp01(blended * (0.84 + confidence * 0.12)), confidence)
    }

    private func modelScore(
        crowd: Double,
        hour: Int,
        lighting: Double,
        transport: String
    ) -> Double? {
        guard let model else { return nil }

        let input: [String: MLFeatureValue] = [
            "crowd": MLFeatureValue(int64: Int64(clampToFive(crowd).rounded())),
            "hour": MLFeatureValue(int64: Int64((hour % 24 + 24) % 24)),
            "lighting": MLFeatureValue(int64: Int64(clampToFive(lighting).rounded())),
            "transport_walk": MLFeatureValue(int64: transport == "walk" ? 1 : 0),
            "transport_metro": MLFeatureValue(int64: transport == "metro" ? 1 : 0),
            "transport_bus": MLFeatureValue(int64: transport == "bus" ? 1 : 0)
        ]

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: input)
            let output = try model.prediction(from: provider)

            for preferredName in ["label", "target", "value", "predictedValue"] {
                if let value = numericValue(from: output.featureValue(for: preferredName)) {
                    return value
                }
            }

            for name in output.featureNames {
                if let value = numericValue(from: output.featureValue(for: name)) {
                    return value
                }
            }
        } catch {
            print("❌ Error en predicción Core ML: \(error)")
        }

        return nil
    }

    private func numericValue(from featureValue: MLFeatureValue?) -> Double? {
        guard let featureValue else { return nil }

        switch featureValue.type {
        case .double:
            return featureValue.doubleValue
        case .int64:
            return Double(featureValue.int64Value)
        default:
            return nil
        }
    }

    private func normalizeModelOutput(_ value: Double) -> Double {
        if value <= 1 { return clamp01(value) }
        return clamp01(1 - ((value - 1) / 4))
    }

    private func fallbackScore(
        crowd: Double,
        lighting: Double,
        hour: Int,
        transport: String
    ) -> Double {
        let crowdRisk = clamp01((clampToFive(crowd) - 1) / 4)
        let lightingRisk = clamp01(1 - ((clampToFive(lighting) - 1) / 4))
        let hourRisk = clamp01(Double(hour) / 23.0)
        let walkRisk = transport == "walk" ? 1.0 : 0.0
        let metroRisk = transport == "metro" ? 0.55 : 0.0
        let busRisk = transport == "bus" ? 0.68 : 0.0

        let features = [crowdRisk, lightingRisk, hourRisk, walkRisk, metroRisk, busRisk]
        let weights = [0.26, 0.28, 0.18, 0.12, 0.06, 0.10]

        var score = 0.0
        vDSP_dotprD(features, 1, weights, 1, &score, vDSP_Length(weights.count))
        return clamp01(score)
    }

    private func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func clampToFive(_ value: Double) -> Double {
        min(5, max(1, value))
    }
}

private enum TransitStationCatalog {
    struct SegmentInfo {
        var line: String
        var from: String
        var to: String
        var key: String
    }

    private struct Anchor {
        var station: String
        var coordinate: CLLocationCoordinate2D
    }

    static func canonicalSegmentKey(segmentId: String) -> String? {
        segmentInfo(segmentId: segmentId)?.key
    }

    static func canonicalSegmentKey(line: String, from: String, to: String) -> String {
        let names = [from.heatmapKey, to.heatmapKey].sorted().joined(separator: ":")
        return "\(normalizedLine(line)):\(names)"
    }

    static func segmentInfo(segmentId: String) -> SegmentInfo? {
        let parts = segmentId.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let line = normalizedLine(parts[0])
        guard let stations = stationRoutes[line] else { return nil }
        let tailKey = parts[1].heatmapKey

        for from in stations {
            for to in stations where from != to {
                if "\(from)_\(to)".heatmapKey == tailKey {
                    return SegmentInfo(
                        line: line,
                        from: from,
                        to: to,
                        key: canonicalSegmentKey(line: line, from: from, to: to)
                    )
                }
            }
        }

        return nil
    }

    static func coordinate(line: String, stationName: String) -> CLLocationCoordinate2D? {
        let line = normalizedLine(line)
        guard let route = stationRoutes[line],
              let stationIndex = route.firstIndex(where: { $0.heatmapKey == stationName.heatmapKey }),
              let anchors = stationAnchors[line] else { return nil }

        let indexedAnchors = anchors.compactMap { anchor -> (index: Int, coordinate: CLLocationCoordinate2D)? in
            guard let index = route.firstIndex(where: { $0.heatmapKey == anchor.station.heatmapKey }) else { return nil }
            return (index, anchor.coordinate)
        }
        .sorted { $0.index < $1.index }

        if let exact = indexedAnchors.first(where: { $0.index == stationIndex }) {
            return exact.coordinate
        }

        let lower = indexedAnchors.last { $0.index < stationIndex }
        let upper = indexedAnchors.first { $0.index > stationIndex }

        switch (lower, upper) {
        case let (.some(a), .some(b)):
            let progress = Double(stationIndex - a.index) / Double(b.index - a.index)
            return CLLocationCoordinate2D(
                latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * progress,
                longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * progress
            )
        case let (.some(anchor), nil), let (nil, .some(anchor)):
            return anchor.coordinate
        default:
            return nil
        }
    }

    private static func normalizedLine(_ line: String) -> String {
        line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: "LINEA ", with: "L")
            .replacingOccurrences(of: "LINE ", with: "L")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static let stationRoutes: [String: [String]] = [
        "L1": [
            "Observatorio", "Tacubaya", "Juanacatlán", "Chapultepec", "Sevilla", "Insurgentes",
            "Cuauhtémoc", "Balderas", "Salto del Agua", "Isabel la Católica", "Pino Suárez",
            "Merced", "Candelaria", "San Lázaro", "Moctezuma", "Balbuena",
            "Boulevard Puerto Aéreo", "Gómez Farías", "Gómez Morín", "Zaragoza", "Pantitlán"
        ],
        "L2": [
            "Cuatro Caminos", "Panteones", "Tacuba", "Cuitláhuac", "Popotla", "Colegio Militar",
            "Normal", "San Cosme", "Revolución", "Hidalgo", "Bellas Artes", "Allende", "Zócalo",
            "Pino Suárez", "San Antonio Abad", "Chabacano", "Viaducto", "Xola",
            "Villa de Cortés", "Nativitas", "Portales", "Ermita", "General Anaya", "Tasqueña"
        ],
        "L3": [
            "Indios Verdes", "Deportivo 18 de Marzo", "Potrero", "La Raza", "Tlatelolco",
            "Guerrero", "Hidalgo", "Juárez", "Balderas", "Niños Héroes", "Hospital General",
            "Centro Médico", "Etiopía", "Eugenia", "División del Norte", "Zapata", "Coyoacán",
            "Viveros", "Miguel Ángel de Quevedo", "Copilco", "Universidad"
        ],
        "L4": [
            "Martín Carrera", "Talismán", "Bondojito", "Consulado", "Canal del Norte",
            "Morelos", "Candelaria", "Fray Servando", "Jamaica", "Santa Anita"
        ],
        "L5": [
            "Politécnico", "Instituto del Petróleo", "Autobuses del Norte", "La Raza",
            "Misterios", "Valle Gómez", "Consulado", "Eduardo Molina", "Aragón",
            "Oceanía", "Terminal Aérea", "Hangares", "Pantitlán"
        ],
        "L6": [
            "El Rosario", "Tezozómoc", "UAM Azcapotzalco", "Ferrería", "Norte 45",
            "Vallejo", "Instituto del Petróleo", "Lindavista", "Deportivo 18 de Marzo",
            "Martín Carrera"
        ],
        "L7": [
            "El Rosario", "Aquiles Serdán", "Camarones", "Refinería", "Tacuba",
            "San Joaquín", "Polanco", "Auditorio", "Constituyentes", "Tacubaya",
            "San Pedro de los Pinos", "San Antonio", "Mixcoac", "Barranca del Muerto"
        ],
        "L8": [
            "Garibaldi", "Bellas Artes", "San Juan de Letrán", "Salto del Agua", "Doctores",
            "Obrera", "Chabacano", "La Viga", "Santa Anita", "Iztacalco", "Apatlaco",
            "Aculco", "Escuadrón 201", "Atlalilco", "Iztapalapa", "Cerro de la Estrella",
            "UAM I", "Constitución de 1917"
        ],
        "L9": [
            "Tacubaya", "Patriotismo", "Chilpancingo", "Centro Médico", "Lázaro Cárdenas",
            "Chabacano", "Jamaica", "Mixiuhca", "Velódromo", "Ciudad Deportiva",
            "Puebla", "Pantitlán"
        ],
        "L12": [
            "Zapata", "Mixcoac", "Insurgentes Sur", "Hospital 12 de Octubre", "Periférico",
            "Zapotitlán", "Nopalera", "Olivos", "Tezonco", "Periferico Oriente", "Calle 11",
            "Lomas Estrella", "San Andrés Tomatlán", "Culhuacán", "Atlalilco", "Mexicaltzingo",
            "Ermita", "Eje Central", "Parque de los Venados"
        ],
        "MB1": [
            "Indios Verdes", "Eje Central", "Deportivo 18 de Marzo", "Buenavista", "Reforma",
            "Insurgentes", "Sonora", "Campeche", "Chilpancingo", "Ciudad de los Deportes",
            "El Caminero"
        ],
        "MB2": [
            "Tepalcates", "Eje 8", "Iztapalapa", "Ermita Iztapalapa", "Chabacano",
            "Centro Médico", "Tacubaya"
        ],
        "MB3": [
            "Tenango", "Estadio Azteca", "Villa Olímpica", "CU", "Copilco", "Viveros"
        ],
        "TL": [
            "Taxqueña", "Tasqueña", "Huipulco", "Periférico", "Velódromo del Pedregal", "Xochimilco"
        ],
    ]

    private static let stationAnchors: [String: [Anchor]] = [
        "L1": [
            Anchor(station: "Observatorio", coordinate: CLLocationCoordinate2D(latitude: 19.398, longitude: -99.200)),
            Anchor(station: "Tacubaya", coordinate: CLLocationCoordinate2D(latitude: 19.403, longitude: -99.187)),
            Anchor(station: "Chapultepec", coordinate: CLLocationCoordinate2D(latitude: 19.420, longitude: -99.176)),
            Anchor(station: "Balderas", coordinate: CLLocationCoordinate2D(latitude: 19.427, longitude: -99.149)),
            Anchor(station: "Pino Suárez", coordinate: CLLocationCoordinate2D(latitude: 19.425, longitude: -99.133)),
            Anchor(station: "San Lázaro", coordinate: CLLocationCoordinate2D(latitude: 19.431, longitude: -99.114)),
            Anchor(station: "Pantitlán", coordinate: CLLocationCoordinate2D(latitude: 19.415, longitude: -99.073)),
        ],
        "L2": [
            Anchor(station: "Cuatro Caminos", coordinate: CLLocationCoordinate2D(latitude: 19.459, longitude: -99.216)),
            Anchor(station: "Tacuba", coordinate: CLLocationCoordinate2D(latitude: 19.459, longitude: -99.188)),
            Anchor(station: "Hidalgo", coordinate: CLLocationCoordinate2D(latitude: 19.437, longitude: -99.147)),
            Anchor(station: "Pino Suárez", coordinate: CLLocationCoordinate2D(latitude: 19.425, longitude: -99.133)),
            Anchor(station: "Chabacano", coordinate: CLLocationCoordinate2D(latitude: 19.408, longitude: -99.135)),
            Anchor(station: "Tasqueña", coordinate: CLLocationCoordinate2D(latitude: 19.344, longitude: -99.142)),
        ],
        "L3": [
            Anchor(station: "Indios Verdes", coordinate: CLLocationCoordinate2D(latitude: 19.495, longitude: -99.119)),
            Anchor(station: "La Raza", coordinate: CLLocationCoordinate2D(latitude: 19.468, longitude: -99.139)),
            Anchor(station: "Hidalgo", coordinate: CLLocationCoordinate2D(latitude: 19.437, longitude: -99.147)),
            Anchor(station: "Balderas", coordinate: CLLocationCoordinate2D(latitude: 19.427, longitude: -99.149)),
            Anchor(station: "Centro Médico", coordinate: CLLocationCoordinate2D(latitude: 19.406, longitude: -99.155)),
            Anchor(station: "Zapata", coordinate: CLLocationCoordinate2D(latitude: 19.370, longitude: -99.165)),
            Anchor(station: "Universidad", coordinate: CLLocationCoordinate2D(latitude: 19.324, longitude: -99.174)),
        ],
        "L4": [
            Anchor(station: "Martín Carrera", coordinate: CLLocationCoordinate2D(latitude: 19.485, longitude: -99.104)),
            Anchor(station: "Consulado", coordinate: CLLocationCoordinate2D(latitude: 19.458, longitude: -99.114)),
            Anchor(station: "Morelos", coordinate: CLLocationCoordinate2D(latitude: 19.439, longitude: -99.119)),
            Anchor(station: "Candelaria", coordinate: CLLocationCoordinate2D(latitude: 19.432, longitude: -99.124)),
            Anchor(station: "Jamaica", coordinate: CLLocationCoordinate2D(latitude: 19.409, longitude: -99.122)),
            Anchor(station: "Santa Anita", coordinate: CLLocationCoordinate2D(latitude: 19.402, longitude: -99.121)),
        ],
        "L5": [
            Anchor(station: "Politécnico", coordinate: CLLocationCoordinate2D(latitude: 19.500, longitude: -99.149)),
            Anchor(station: "Instituto del Petróleo", coordinate: CLLocationCoordinate2D(latitude: 19.490, longitude: -99.146)),
            Anchor(station: "La Raza", coordinate: CLLocationCoordinate2D(latitude: 19.468, longitude: -99.139)),
            Anchor(station: "Consulado", coordinate: CLLocationCoordinate2D(latitude: 19.458, longitude: -99.114)),
            Anchor(station: "Oceanía", coordinate: CLLocationCoordinate2D(latitude: 19.445, longitude: -99.087)),
            Anchor(station: "Pantitlán", coordinate: CLLocationCoordinate2D(latitude: 19.415, longitude: -99.073)),
        ],
        "L6": [
            Anchor(station: "El Rosario", coordinate: CLLocationCoordinate2D(latitude: 19.504, longitude: -99.200)),
            Anchor(station: "UAM Azcapotzalco", coordinate: CLLocationCoordinate2D(latitude: 19.490, longitude: -99.186)),
            Anchor(station: "Instituto del Petróleo", coordinate: CLLocationCoordinate2D(latitude: 19.490, longitude: -99.146)),
            Anchor(station: "Deportivo 18 de Marzo", coordinate: CLLocationCoordinate2D(latitude: 19.483, longitude: -99.126)),
            Anchor(station: "Martín Carrera", coordinate: CLLocationCoordinate2D(latitude: 19.485, longitude: -99.104)),
        ],
        "L7": [
            Anchor(station: "El Rosario", coordinate: CLLocationCoordinate2D(latitude: 19.504, longitude: -99.200)),
            Anchor(station: "Tacuba", coordinate: CLLocationCoordinate2D(latitude: 19.459, longitude: -99.188)),
            Anchor(station: "Polanco", coordinate: CLLocationCoordinate2D(latitude: 19.433, longitude: -99.191)),
            Anchor(station: "Auditorio", coordinate: CLLocationCoordinate2D(latitude: 19.425, longitude: -99.192)),
            Anchor(station: "Tacubaya", coordinate: CLLocationCoordinate2D(latitude: 19.403, longitude: -99.187)),
            Anchor(station: "Mixcoac", coordinate: CLLocationCoordinate2D(latitude: 19.376, longitude: -99.187)),
            Anchor(station: "Barranca del Muerto", coordinate: CLLocationCoordinate2D(latitude: 19.361, longitude: -99.190)),
        ],
        "L8": [
            Anchor(station: "Garibaldi", coordinate: CLLocationCoordinate2D(latitude: 19.444, longitude: -99.139)),
            Anchor(station: "Salto del Agua", coordinate: CLLocationCoordinate2D(latitude: 19.427, longitude: -99.142)),
            Anchor(station: "Chabacano", coordinate: CLLocationCoordinate2D(latitude: 19.408, longitude: -99.135)),
            Anchor(station: "Santa Anita", coordinate: CLLocationCoordinate2D(latitude: 19.402, longitude: -99.121)),
            Anchor(station: "Atlalilco", coordinate: CLLocationCoordinate2D(latitude: 19.356, longitude: -99.101)),
            Anchor(station: "Constitución de 1917", coordinate: CLLocationCoordinate2D(latitude: 19.345, longitude: -99.063)),
        ],
        "L9": [
            Anchor(station: "Tacubaya", coordinate: CLLocationCoordinate2D(latitude: 19.403, longitude: -99.187)),
            Anchor(station: "Chilpancingo", coordinate: CLLocationCoordinate2D(latitude: 19.407, longitude: -99.169)),
            Anchor(station: "Centro Médico", coordinate: CLLocationCoordinate2D(latitude: 19.406, longitude: -99.155)),
            Anchor(station: "Chabacano", coordinate: CLLocationCoordinate2D(latitude: 19.408, longitude: -99.135)),
            Anchor(station: "Jamaica", coordinate: CLLocationCoordinate2D(latitude: 19.409, longitude: -99.122)),
            Anchor(station: "Ciudad Deportiva", coordinate: CLLocationCoordinate2D(latitude: 19.409, longitude: -99.093)),
            Anchor(station: "Pantitlán", coordinate: CLLocationCoordinate2D(latitude: 19.415, longitude: -99.073)),
        ],
        "L12": [
            Anchor(station: "Mixcoac", coordinate: CLLocationCoordinate2D(latitude: 19.376, longitude: -99.187)),
            Anchor(station: "Zapata", coordinate: CLLocationCoordinate2D(latitude: 19.370, longitude: -99.165)),
            Anchor(station: "Ermita", coordinate: CLLocationCoordinate2D(latitude: 19.360, longitude: -99.142)),
            Anchor(station: "Atlalilco", coordinate: CLLocationCoordinate2D(latitude: 19.356, longitude: -99.101)),
            Anchor(station: "Periferico Oriente", coordinate: CLLocationCoordinate2D(latitude: 19.317, longitude: -99.074)),
            Anchor(station: "Zapotitlán", coordinate: CLLocationCoordinate2D(latitude: 19.296, longitude: -99.043)),
            Anchor(station: "Parque de los Venados", coordinate: CLLocationCoordinate2D(latitude: 19.370, longitude: -99.158)),
        ],
        "MB1": [
            Anchor(station: "Indios Verdes", coordinate: CLLocationCoordinate2D(latitude: 19.495, longitude: -99.119)),
            Anchor(station: "Buenavista", coordinate: CLLocationCoordinate2D(latitude: 19.448, longitude: -99.152)),
            Anchor(station: "Insurgentes", coordinate: CLLocationCoordinate2D(latitude: 19.423, longitude: -99.163)),
            Anchor(station: "Chilpancingo", coordinate: CLLocationCoordinate2D(latitude: 19.407, longitude: -99.169)),
            Anchor(station: "El Caminero", coordinate: CLLocationCoordinate2D(latitude: 19.280, longitude: -99.170)),
        ],
        "MB2": [
            Anchor(station: "Tepalcates", coordinate: CLLocationCoordinate2D(latitude: 19.391, longitude: -99.048)),
            Anchor(station: "Iztapalapa", coordinate: CLLocationCoordinate2D(latitude: 19.357, longitude: -99.093)),
            Anchor(station: "Chabacano", coordinate: CLLocationCoordinate2D(latitude: 19.408, longitude: -99.135)),
            Anchor(station: "Centro Médico", coordinate: CLLocationCoordinate2D(latitude: 19.406, longitude: -99.155)),
            Anchor(station: "Tacubaya", coordinate: CLLocationCoordinate2D(latitude: 19.403, longitude: -99.187)),
        ],
        "MB3": [
            Anchor(station: "Tenango", coordinate: CLLocationCoordinate2D(latitude: 19.280, longitude: -99.170)),
            Anchor(station: "Estadio Azteca", coordinate: CLLocationCoordinate2D(latitude: 19.303, longitude: -99.150)),
            Anchor(station: "CU", coordinate: CLLocationCoordinate2D(latitude: 19.324, longitude: -99.184)),
            Anchor(station: "Viveros", coordinate: CLLocationCoordinate2D(latitude: 19.353, longitude: -99.170)),
        ],
        "TL": [
            Anchor(station: "Taxqueña", coordinate: CLLocationCoordinate2D(latitude: 19.344, longitude: -99.142)),
            Anchor(station: "Tasqueña", coordinate: CLLocationCoordinate2D(latitude: 19.344, longitude: -99.142)),
            Anchor(station: "Huipulco", coordinate: CLLocationCoordinate2D(latitude: 19.302, longitude: -99.139)),
            Anchor(station: "Periférico", coordinate: CLLocationCoordinate2D(latitude: 19.292, longitude: -99.138)),
            Anchor(station: "Xochimilco", coordinate: CLLocationCoordinate2D(latitude: 19.256, longitude: -99.104)),
        ],
    ]
}

private extension Array where Element == FSReport {
    func mean(_ keyPath: KeyPath<FSReport, Double>) -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1[keyPath: keyPath] } / Double(count)
    }

    var representativeHour: Int? {
        guard !isEmpty else { return nil }
        let average = reduce(0) { $0 + (($1.hour % 24 + 24) % 24) } / count
        return average
    }
}

extension TimeFilter {
    var representativeHour: Int {
        switch self {
        case .all: 16
        case .morning: 8
        case .afternoon: 16
        case .night: 22
        }
    }

    var riskPrior: Double {
        switch self {
        case .all: 0.46
        case .morning: 0.22
        case .afternoon: 0.34
        case .night: 0.82
        }
    }

    func contains(hour: Int) -> Bool {
        let normalized = (hour % 24 + 24) % 24
        switch self {
        case .all:
            return true
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
            .lowercased()
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
