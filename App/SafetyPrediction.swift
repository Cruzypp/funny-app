import Accelerate
import CoreLocation
import CoreML
import Foundation
import Observation
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum SafetyTimeFilter: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case night

    var id: String { rawValue }

    var representativeHour: Int {
        switch self {
        case .morning: 8
        case .afternoon: 16
        case .night: 22
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
}

enum TransportFilter: String, CaseIterable, Identifiable {
    case all
    case walk
    case metro
    case bus

    var id: String { rawValue }

    func matches(_ transportType: String) -> Bool {
        guard self != .all else { return true }
        return transportType.normalizedSafetyKey == rawValue
    }
}

struct SafetyReport: Identifiable, Equatable {
    var id: String
    var segmentID: String
    var transportType: String
    var hour: Int
    var crowd: Double
    var lighting: Double
    var safety: Double
    var timestamp: Date?
}

struct SafetySegment: Identifiable, Equatable {
    var id: String
    var from: String
    var to: String
    var line: String
    var reportsCount: Int
    var riskScore: Double
    var safetyLabel: String
    var transportType: String

    var title: String { "\(from) - \(to)" }
}

struct SafetyStation: Identifiable, Equatable {
    var id: String
    var name: String
    var line: String
    var type: String
    var lat: Double
    var lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct SafetySnapshot {
    var reports: [SafetyReport]
    var segments: [SafetySegment]
    var stations: [SafetyStation]

    static let empty = SafetySnapshot(reports: [], segments: [], stations: [])
}

struct SafetyZonePrediction: Identifiable {
    var id: String
    var segmentID: String
    var title: String
    var coordinate: CLLocationCoordinate2D
    var radiusMeters: CLLocationDistance
    var riskScore: Double
    var level: SafetyLevel
    var reportCount: Int
    var line: String
    var transportType: String
    var confidence: Double

    var opacity: Double {
        switch level {
        case .high: 0.28
        case .medium: 0.36
        case .low: 0.44
        }
    }

    var summary: String {
        let score = Int((riskScore * 100).rounded())
        return "\(reportCount) reportes - \(transportType) - riesgo \(score)%"
    }
}

extension SafetyLevel {
    var heatColor: Color {
        switch self {
        case .high: T.safe
        case .medium: T.warn
        case .low: T.risk
        }
    }

    static func fromRiskScore(_ score: Double) -> SafetyLevel {
        switch score {
        case ..<0.34: .high
        case ..<0.66: .medium
        default: .low
        }
    }
}

private struct SafetyFeatureVector {
    var reportedRisk: Double
    var lightingRisk: Double
    var crowdRisk: Double
    var segmentRisk: Double
    var timeRisk: Double
    var reportsCount: Double
    var hourSin: Double
    var hourCos: Double
    var transportType: String

    var mlFeatures: [String: MLFeatureValue] {
        [
            "reported_risk": MLFeatureValue(double: reportedRisk),
            "lighting_risk": MLFeatureValue(double: lightingRisk),
            "crowd_risk": MLFeatureValue(double: crowdRisk),
            "segment_risk": MLFeatureValue(double: segmentRisk),
            "time_risk": MLFeatureValue(double: timeRisk),
            "reports_count": MLFeatureValue(double: reportsCount),
            "hour_sin": MLFeatureValue(double: hourSin),
            "hour_cos": MLFeatureValue(double: hourCos),
            "transport_walk": MLFeatureValue(double: transportType == "walk" ? 1 : 0),
            "transport_metro": MLFeatureValue(double: transportType == "metro" ? 1 : 0),
            "transport_bus": MLFeatureValue(double: transportType == "bus" ? 1 : 0),
        ]
    }

    var fallbackInputs: [Double] {
        [reportedRisk, lightingRisk, crowdRisk, segmentRisk, timeRisk]
    }
}

struct SafetyZonePredictor {
    private let model: MLModel?

    init(modelName: String = "SafetyZoneRegressor") {
        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            let configuration = MLModelConfiguration()
            model = try? MLModel(contentsOf: compiledURL, configuration: configuration)
        } else {
            model = nil
        }
    }

    func riskScore(
        for segment: SafetySegment,
        reports: [SafetyReport],
        timeFilter: SafetyTimeFilter,
        transportFilter: TransportFilter
    ) -> (score: Double, confidence: Double, reportCount: Int) {
        let relevantReports = reports.filter { report in
            report.segmentID.normalizedSafetyKey == segment.id.normalizedSafetyKey &&
            timeFilter.contains(hour: report.hour) &&
            transportFilter.matches(report.transportType)
        }

        let segmentReports = relevantReports.isEmpty ? reports.filter {
            $0.segmentID.normalizedSafetyKey == segment.id.normalizedSafetyKey
        } : relevantReports

        let featureVector = makeFeatureVector(
            segment: segment,
            reports: segmentReports,
            hour: timeFilter.representativeHour
        )

        let rawScore = modelRiskScore(for: featureVector) ?? fallbackRiskScore(for: featureVector)
        let confidence = min(1, max(Double(segmentReports.count), Double(segment.reportsCount)) / 12)
        let blendedScore = (rawScore * (0.72 + confidence * 0.18)) + (featureVector.segmentRisk * (0.28 - confidence * 0.18))

        return (
            score: clamp(blendedScore),
            confidence: confidence,
            reportCount: max(segmentReports.count, segment.reportsCount)
        )
    }

    private func makeFeatureVector(segment: SafetySegment, reports: [SafetyReport], hour: Int) -> SafetyFeatureVector {
        let safeMean = reports.mean(\.safety) ?? (5 - clamp(segment.riskScore) * 4)
        let lightingMean = reports.mean(\.lighting) ?? safeMean
        let crowdMean = reports.mean(\.crowd) ?? 3
        let radians = Double(hour) / 24 * 2 * Double.pi

        return SafetyFeatureVector(
            reportedRisk: clamp(1 - ((safeMean - 1) / 4)),
            lightingRisk: clamp(1 - ((lightingMean - 1) / 4)),
            crowdRisk: clamp(1 - ((crowdMean - 1) / 4)),
            segmentRisk: clamp(segment.riskScore),
            timeRisk: timeRisk(for: hour),
            reportsCount: Double(max(reports.count, segment.reportsCount)),
            hourSin: sin(radians),
            hourCos: cos(radians),
            transportType: segment.transportType.normalizedSafetyKey
        )
    }

    private func modelRiskScore(for features: SafetyFeatureVector) -> Double? {
        guard let model else { return nil }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: features.mlFeatures)
            let output = try model.prediction(from: provider)

            if let risk = numericOutput(named: "risk_score", from: output) {
                return clamp(risk)
            }

            for featureName in output.featureNames {
                if let value = numericOutput(named: featureName, from: output) {
                    return clamp(value)
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func numericOutput(named name: String, from provider: MLFeatureProvider) -> Double? {
        guard let value = provider.featureValue(for: name) else { return nil }

        switch value.type {
        case .double:
            return value.doubleValue
        case .int64:
            return Double(value.int64Value)
        default:
            return nil
        }
    }

    private func fallbackRiskScore(for features: SafetyFeatureVector) -> Double {
        let weights = [0.38, 0.18, 0.12, 0.24, 0.08]
        var result = 0.0
        vDSP_dotprD(features.fallbackInputs, 1, weights, 1, &result, vDSP_Length(weights.count))
        return clamp(result)
    }

    private func timeRisk(for hour: Int) -> Double {
        switch hour {
        case 19...23, 0..<6: 0.88
        case 12..<19: 0.38
        default: 0.24
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct SafetyHeatmapBuilder {
    private let predictor = SafetyZonePredictor()

    func zones(
        snapshot: SafetySnapshot,
        timeFilter: SafetyTimeFilter,
        transportFilter: TransportFilter
    ) -> [SafetyZonePrediction] {
        let stationsByName = snapshot.stations.reduce(into: [String: SafetyStation]()) { result, station in
            let key = station.name.normalizedSafetyKey
            result[key] = result[key] ?? station
        }

        return snapshot.segments.compactMap { segment -> SafetyZonePrediction? in
            guard transportFilter.matches(segment.transportType) else { return nil }
            guard let coordinate = coordinate(for: segment, stationsByName: stationsByName) else { return nil }

            let prediction = predictor.riskScore(
                for: segment,
                reports: snapshot.reports,
                timeFilter: timeFilter,
                transportFilter: transportFilter
            )

            let radius = 180 + min(620, sqrt(Double(max(prediction.reportCount, 1))) * 72)

            return SafetyZonePrediction(
                id: "\(segment.id)-\(timeFilter.rawValue)-\(transportFilter.rawValue)",
                segmentID: segment.id,
                title: segment.title,
                coordinate: coordinate,
                radiusMeters: radius,
                riskScore: prediction.score,
                level: .fromRiskScore(prediction.score),
                reportCount: prediction.reportCount,
                line: segment.line,
                transportType: segment.transportType,
                confidence: prediction.confidence
            )
        }
        .sorted { $0.riskScore > $1.riskScore }
    }

    private func coordinate(
        for segment: SafetySegment,
        stationsByName: [String: SafetyStation]
    ) -> CLLocationCoordinate2D? {
        let from = stationsByName[segment.from.normalizedSafetyKey]
        let to = stationsByName[segment.to.normalizedSafetyKey]

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
}

protocol SafetyDataRepository {
    func fetchSnapshot() async throws -> SafetySnapshot
}

struct DefaultSafetyDataRepository: SafetyDataRepository {
    func fetchSnapshot() async throws -> SafetySnapshot {
        #if canImport(FirebaseFirestore)
        return try await FirestoreSafetyDataRepository().fetchSnapshot()
        #else
        return try await SampleSafetyDataRepository().fetchSnapshot()
        #endif
    }
}

struct SampleSafetyDataRepository: SafetyDataRepository {
    func fetchSnapshot() async throws -> SafetySnapshot {
        SafetySnapshot.sample
    }
}

#if canImport(FirebaseFirestore)
struct FirestoreSafetyDataRepository: SafetyDataRepository {
    private let db = Firestore.firestore()

    func fetchSnapshot() async throws -> SafetySnapshot {
        async let reports = fetchReports()
        async let segments = fetchSegments()
        async let stations = fetchStations()
        return try await SafetySnapshot(reports: reports, segments: segments, stations: stations)
    }

    private func fetchReports() async throws -> [SafetyReport] {
        let snapshot = try await documents(in: "reports")
        return snapshot.documents.map { document in
            let data = document.data()
            let hour = intValue(data["hour"]) ?? hourFromTimestamp(data["timestamp"])
            return SafetyReport(
                id: document.documentID,
                segmentID: stringValue(data["segment_id"], fallback: ""),
                transportType: stringValue(data["transport_type"], fallback: "metro"),
                hour: hour ?? 0,
                crowd: doubleValue(data["crowd"], fallback: 3),
                lighting: doubleValue(data["lighting"], fallback: 3),
                safety: doubleValue(data["safety"], fallback: 3),
                timestamp: dateValue(data["timestamp"])
            )
        }
    }

    private func fetchSegments() async throws -> [SafetySegment] {
        let snapshot = try await documents(in: "segments")
        return snapshot.documents.map { document in
            let data = document.data()
            return SafetySegment(
                id: document.documentID,
                from: stringValue(data["from"], fallback: ""),
                to: stringValue(data["to"], fallback: ""),
                line: stringValue(data["line"], fallback: ""),
                reportsCount: intValue(data["reports_count"]) ?? 0,
                riskScore: doubleValue(data["risk_score"], fallback: 0.5),
                safetyLabel: stringValue(data["safety_label"], fallback: "C"),
                transportType: stringValue(data["transport_type"], fallback: "metro")
            )
        }
    }

    private func fetchStations() async throws -> [SafetyStation] {
        let snapshot = try await documents(in: "stations")
        return snapshot.documents.map { document in
            let data = document.data()
            return SafetyStation(
                id: document.documentID,
                name: stringValue(data["name"], fallback: document.documentID),
                line: stringValue(data["line"], fallback: ""),
                type: stringValue(data["type"], fallback: ""),
                lat: doubleValue(data["lat"], fallback: 19.4326),
                lng: doubleValue(data["lng"], fallback: -99.1332)
            )
        }
    }

    private func documents(in collection: String) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            db.collection(collection).getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirestoreSafetyDataRepository", code: -1))
                }
            }
        }
    }

    private func stringValue(_ value: Any?, fallback: String) -> String {
        value as? String ?? fallback
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func doubleValue(_ value: Any?, fallback: Double) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let double = Double(string) { return double }
        return fallback
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }

    private func hourFromTimestamp(_ value: Any?) -> Int? {
        guard let date = dateValue(value) else { return nil }
        return Calendar.current.component(.hour, from: date)
    }
}
#endif

@MainActor
@Observable
final class SafetyHeatmapStore {
    @ObservationIgnored private let repository: SafetyDataRepository
    @ObservationIgnored private let builder = SafetyHeatmapBuilder()

    private(set) var snapshot: SafetySnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var sourceLabel = "Demo local"

    var reportCount: Int {
        let directCount = snapshot.reports.count
        guard directCount == 0 else { return directCount }
        return snapshot.segments.reduce(0) { $0 + $1.reportsCount }
    }

    init(repository: SafetyDataRepository? = nil) {
        self.repository = repository ?? DefaultSafetyDataRepository()
        snapshot = .sample
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            snapshot = try await repository.fetchSnapshot()
            errorMessage = nil
            lastUpdated = Date()
            sourceLabel = firestoreAvailable ? "Firebase" : "Demo local"
        } catch {
            snapshot = .sample
            errorMessage = "No pude leer Firebase; usando datos demo."
            sourceLabel = "Demo local"
        }
    }

    func zones(timeFilter: SafetyTimeFilter, transportFilter: TransportFilter) -> [SafetyZonePrediction] {
        builder.zones(snapshot: snapshot, timeFilter: timeFilter, transportFilter: transportFilter)
    }

    func topInsight(timeFilter: SafetyTimeFilter, transportFilter: TransportFilter) -> SafetyZonePrediction? {
        zones(timeFilter: timeFilter, transportFilter: transportFilter).first
    }

    private var firestoreAvailable: Bool {
        #if canImport(FirebaseFirestore)
        true
        #else
        false
        #endif
    }
}

private extension Array where Element == SafetyReport {
    func mean(_ keyPath: KeyPath<SafetyReport, Double>) -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1[keyPath: keyPath] } / Double(count)
    }
}

private extension String {
    var normalizedSafetyKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
}

private extension SafetySnapshot {
    static let sample = SafetySnapshot(
        reports: [
            .init(id: "r1", segmentID: "L1_balbuena_Moctezuma", transportType: "metro", hour: 22, crowd: 4, lighting: 2, safety: 2, timestamp: nil),
            .init(id: "r2", segmentID: "L1_balbuena_Moctezuma", transportType: "metro", hour: 21, crowd: 3, lighting: 2, safety: 2, timestamp: nil),
            .init(id: "r3", segmentID: "L1_boulevard_puerto_aereo_Balbuena", transportType: "metro", hour: 8, crowd: 4, lighting: 4, safety: 4, timestamp: nil),
            .init(id: "r4", segmentID: "L1_moctezuma_San_Lazaro", transportType: "metro", hour: 23, crowd: 2, lighting: 2, safety: 2, timestamp: nil),
            .init(id: "r5", segmentID: "L1_san_lazaro_Candelaria", transportType: "metro", hour: 20, crowd: 3, lighting: 3, safety: 3, timestamp: nil),
            .init(id: "r6", segmentID: "L1_candelaria_Merced", transportType: "metro", hour: 14, crowd: 5, lighting: 4, safety: 4, timestamp: nil),
            .init(id: "r7", segmentID: "L1_merced_Pino_Suarez", transportType: "metro", hour: 23, crowd: 2, lighting: 2, safety: 2, timestamp: nil),
            .init(id: "r8", segmentID: "L1_pino_suarez_Isabel_la_Catolica", transportType: "metro", hour: 18, crowd: 4, lighting: 4, safety: 4, timestamp: nil),
            .init(id: "r9", segmentID: "L1_salto_del_agua_Balderas", transportType: "metro", hour: 22, crowd: 2, lighting: 1, safety: 2, timestamp: nil),
            .init(id: "r10", segmentID: "L1_balderas_Cuauhtemoc", transportType: "metro", hour: 15, crowd: 4, lighting: 3, safety: 3, timestamp: nil),
            .init(id: "r11", segmentID: "walk_sonora_alvaro_obregon", transportType: "walk", hour: 23, crowd: 2, lighting: 2, safety: 2, timestamp: nil),
            .init(id: "r12", segmentID: "bus_insurgentes_sevilla", transportType: "bus", hour: 19, crowd: 4, lighting: 3, safety: 3, timestamp: nil),
        ],
        segments: [
            .init(id: "L1_pantitlan_Zaragoza", from: "Pantitlán", to: "Zaragoza", line: "L1", reportsCount: 7, riskScore: 0.31, safetyLabel: "B", transportType: "metro"),
            .init(id: "L1_zaragoza_Gomez_Farias", from: "Zaragoza", to: "Gómez Farías", line: "L1", reportsCount: 6, riskScore: 0.28, safetyLabel: "B", transportType: "metro"),
            .init(id: "L1_gomez_farias_Boulevard_Puerto_Aereo", from: "Gómez Farías", to: "Boulevard Puerto Aéreo", line: "L1", reportsCount: 5, riskScore: 0.33, safetyLabel: "B", transportType: "metro"),
            .init(id: "L1_boulevard_puerto_aereo_Balbuena", from: "Boulevard Puerto Aéreo", to: "Balbuena", line: "L1", reportsCount: 8, riskScore: 0.24, safetyLabel: "A", transportType: "metro"),
            .init(id: "L1_balbuena_Moctezuma", from: "Balbuena", to: "Moctezuma", line: "L1", reportsCount: 10, riskScore: 0.4016, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_moctezuma_San_Lazaro", from: "Moctezuma", to: "San Lázaro", line: "L1", reportsCount: 12, riskScore: 0.57, safetyLabel: "D", transportType: "metro"),
            .init(id: "L1_san_lazaro_Candelaria", from: "San Lázaro", to: "Candelaria", line: "L1", reportsCount: 11, riskScore: 0.45, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_candelaria_Merced", from: "Candelaria", to: "Merced", line: "L1", reportsCount: 9, riskScore: 0.36, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_merced_Pino_Suarez", from: "Merced", to: "Pino Suárez", line: "L1", reportsCount: 13, riskScore: 0.62, safetyLabel: "D", transportType: "metro"),
            .init(id: "L1_pino_suarez_Isabel_la_Catolica", from: "Pino Suárez", to: "Isabel la Católica", line: "L1", reportsCount: 7, riskScore: 0.29, safetyLabel: "B", transportType: "metro"),
            .init(id: "L1_isabel_la_catolica_Salto_del_Agua", from: "Isabel la Católica", to: "Salto del Agua", line: "L1", reportsCount: 7, riskScore: 0.39, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_salto_del_agua_Balderas", from: "Salto del Agua", to: "Balderas", line: "L1", reportsCount: 15, riskScore: 0.67, safetyLabel: "E", transportType: "metro"),
            .init(id: "L1_balderas_Cuauhtemoc", from: "Balderas", to: "Cuauhtémoc", line: "L1", reportsCount: 10, riskScore: 0.42, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_cuauhtemoc_Insurgentes", from: "Cuauhtémoc", to: "Insurgentes", line: "L1", reportsCount: 8, riskScore: 0.48, safetyLabel: "C", transportType: "metro"),
            .init(id: "L1_insurgentes_Sevilla", from: "Insurgentes", to: "Sevilla", line: "L1", reportsCount: 9, riskScore: 0.34, safetyLabel: "B", transportType: "metro"),
            .init(id: "L1_sevilla_Chapultepec", from: "Sevilla", to: "Chapultepec", line: "L1", reportsCount: 6, riskScore: 0.27, safetyLabel: "B", transportType: "metro"),
            .init(id: "walk_sonora_alvaro_obregon", from: "Insurgentes", to: "Sevilla", line: "Roma Norte", reportsCount: 18, riskScore: 0.64, safetyLabel: "D", transportType: "walk"),
            .init(id: "bus_insurgentes_sevilla", from: "Insurgentes", to: "Sevilla", line: "Metrobús L1", reportsCount: 14, riskScore: 0.46, safetyLabel: "C", transportType: "bus"),
        ],
        stations: [
            .init(id: "Pantitlan", name: "Pantitlán", line: "L1", type: "metro", lat: 19.4156, lng: -99.0721),
            .init(id: "Zaragoza", name: "Zaragoza", line: "L1", type: "metro", lat: 19.4118, lng: -99.0824),
            .init(id: "Gomez_Farias", name: "Gómez Farías", line: "L1", type: "metro", lat: 19.4162, lng: -99.0903),
            .init(id: "Boulevard_Puerto_Aereo", name: "Boulevard Puerto Aéreo", line: "L1", type: "metro", lat: 19.4196, lng: -99.0958),
            .init(id: "Balbuena", name: "Balbuena", line: "L1", type: "metro", lat: 19.4220, lng: -99.1110),
            .init(id: "Moctezuma", name: "Moctezuma", line: "L1", type: "metro", lat: 19.4271, lng: -99.1105),
            .init(id: "San_Lazaro", name: "San Lázaro", line: "L1", type: "metro", lat: 19.4303, lng: -99.1148),
            .init(id: "Candelaria", name: "Candelaria", line: "L1", type: "metro", lat: 19.4288, lng: -99.1206),
            .init(id: "Merced", name: "Merced", line: "L1", type: "metro", lat: 19.4269, lng: -99.1261),
            .init(id: "Pino_Suarez", name: "Pino Suárez", line: "L1", type: "metro", lat: 19.4259, lng: -99.1332),
            .init(id: "Isabel_la_Catolica", name: "Isabel la Católica", line: "L1", type: "metro", lat: 19.4264, lng: -99.1375),
            .init(id: "Salto_del_Agua", name: "Salto del Agua", line: "L1", type: "metro", lat: 19.4269, lng: -99.1425),
            .init(id: "Balderas", name: "Balderas", line: "L1", type: "metro", lat: 19.4274, lng: -99.1491),
            .init(id: "Cuauhtemoc", name: "Cuauhtémoc", line: "L1", type: "metro", lat: 19.4257, lng: -99.1543),
            .init(id: "Insurgentes", name: "Insurgentes", line: "L1", type: "metro", lat: 19.4233, lng: -99.1631),
            .init(id: "Sevilla", name: "Sevilla", line: "L1", type: "metro", lat: 19.4212, lng: -99.1707),
            .init(id: "Chapultepec", name: "Chapultepec", line: "L1", type: "metro", lat: 19.4208, lng: -99.1763),
        ]
    )
}
