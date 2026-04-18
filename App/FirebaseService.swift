import FirebaseFirestore
import FirebaseAuth
import Foundation

// MARK: - Singleton de acceso a Firestore
@MainActor
final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private init() {}

    // ─────────────────────────────────────
    // MARK: 1. Usuarios
    // ─────────────────────────────────────

    func fetchUser(uid: String) async throws -> FSUser {
        let doc = try await db.collection("users").document(uid).getDocument()
        return try doc.data(as: FSUser.self)
    }

    func saveUser(_ user: FSUser) async throws {
        guard let uid = user.id else { return }
        try db.collection("users").document(uid).setData(from: user)
    }

    func updatePreferencias(uid: String, preferencias: FSPreferencias) async throws {
        let data: [String: Any] = [
            "preferencias.modo_noche": preferencias.modoNoche,
            "preferencias.nivel_riesgo_tolerado": preferencias.nivelRiesgoTolerado
        ]
        try await db.collection("users").document(uid).updateData(data)
    }

    // ─────────────────────────────────────
    // MARK: 2. Ubicación en tiempo real
    // ─────────────────────────────────────

    func updateLocation(userId: String, lat: Double, lng: Double, estado: EstadoRuta) async throws {
        let location = FSLocation(
            id: userId,
            userId: userId,
            latitud: lat,
            longitud: lng,
            timestamp: Timestamp(),
            estado: estado
        )
        try db.collection("locations").document(userId).setData(from: location)
    }

    /// Observa la ubicación de un contacto en tiempo real
    func observeLocation(userId: String, onChange: @escaping (FSLocation?) -> Void) -> ListenerRegistration {
        db.collection("locations").document(userId)
            .addSnapshotListener { snapshot, _ in
                let location = try? snapshot?.data(as: FSLocation.self)
                onChange(location)
            }
    }

    // ─────────────────────────────────────
    // MARK: 3. Incidentes
    // ─────────────────────────────────────

    func reportIncident(_ incident: FSIncident) async throws {
        try db.collection("incidents").addDocument(from: incident)
    }

    /// Incidentes cerca de una ubicación (últimas 24h)
    func fetchNearbyIncidents(lat: Double, lng: Double) async throws -> [FSIncident] {
        let since = Timestamp(date: Date().addingTimeInterval(-86400))
        let snapshot = try await db.collection("incidents")
            .whereField("hora", isGreaterThan: since)
            .order(by: "hora", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FSIncident.self) }
    }

    /// Para el mapa de calor — todos los incidentes por tipo de hora
    func fetchIncidents(since: Date) async throws -> [FSIncident] {
        let snapshot = try await db.collection("incidents")
            .whereField("hora", isGreaterThan: Timestamp(date: since))
            .order(by: "hora", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FSIncident.self) }
    }

    // ─────────────────────────────────────
    // MARK: 4. Rutas
    // ─────────────────────────────────────

    func saveRoute(_ route: FSRoute) async throws -> String {
        let ref = try db.collection("routes").addDocument(from: route)
        return ref.documentID
    }

    func fetchRouteHistory(userId: String) async throws -> [FSRoute] {
        let snapshot = try await db.collection("routes")
            .whereField("user_id", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FSRoute.self) }
    }

    // ─────────────────────────────────────
    // MARK: 5. Alertas
    // ─────────────────────────────────────

    func triggerAlert(userId: String, tipo: TipoAlerta, rutaId: String?) async throws {
        let alert = FSAlert(
            userId: userId,
            tipo: tipo,
            timestamp: Timestamp(),
            estado: .activa,
            rutaId: rutaId
        )
        try db.collection("alerts").addDocument(from: alert)
    }

    func resolveAlert(alertId: String) async throws {
        try await db.collection("alerts").document(alertId)
            .updateData(["estado": EstadoAlerta.resuelta.rawValue])
    }

    func observeActiveAlerts(userId: String, onChange: @escaping ([FSAlert]) -> Void) -> ListenerRegistration {
        db.collection("alerts")
            .whereField("user_id", isEqualTo: userId)
            .whereField("estado", isEqualTo: "activa")
            .addSnapshotListener { snapshot, _ in
                let alerts = snapshot?.documents.compactMap { try? $0.data(as: FSAlert.self) } ?? []
                onChange(alerts)
            }
    }
}

// MARK: - Encuesta post-viaje → incidente
extension FirebaseService {
    /// Convierte el resultado de ScreenSurvey en un incidente persistido
    func submitSurveyReport(
        userId: String,
        lat: Double, lng: Double,
        safetyScore: Int,
        lightingScore: Int,
        tags: Set<String>,
        comment: String
    ) async throws {
        // Mapear tags a tipo de incidente
        let tipo: TipoIncidente = tags.contains("harassment") ? .acoso
                                : tags.contains("dark")       ? .zonaOscura
                                : .otro

        let incident = FSIncident(
            tipo: tipo,
            latitud: lat,
            longitud: lng,
            hora: Timestamp(),
            usuarioId: userId,
            confiabilidad: safetyScore
        )
        try await reportIncident(incident)
    }
}

// MARK: - Mapa de calor comunitario
extension FirebaseService {
    func fetchHeatmapSnapshot(since: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)) async -> FSHeatmapSnapshot {
        var reports: [FSReport] = []
        var segments: [FSSegment] = []
        var stations: [FSStation] = []
        var incidents: [FSIncident] = []

        do {
            reports = try await fetchSafetyReports(limit: 800)
        } catch {
            print("Heatmap reports error: \(error)")
        }

        do {
            segments = try await fetchSafetySegments(limit: 800)
        } catch {
            print("Heatmap segments error: \(error)")
        }

        do {
            stations = try await fetchSafetyStations(limit: 800)
        } catch {
            print("Heatmap stations error: \(error)")
        }

        do {
            incidents = try await fetchIncidents(since: since)
        } catch {
            print("Heatmap incidents error: \(error)")
        }

        return FSHeatmapSnapshot(
            reports: reports,
            segments: segments,
            stations: stations,
            incidents: incidents
        )
    }

    func fetchSafetyReports(limit: Int = 800) async throws -> [FSReport] {
        let snapshot = try await db.collection("reports")
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.map { document in
            let data = document.data()
            let timestamp = timestampValue(data["timestamp"])
            let hour = intValue(data["hour"])
                ?? timestamp.map { Calendar.current.component(.hour, from: $0.dateValue()) }
                ?? 0

            return FSReport(
                id: document.documentID,
                segmentId: stringValue(data["segment_id"]),
                transportType: stringValue(data["transport_type"], fallback: "metro"),
                hour: hour,
                crowd: doubleValue(data["crowd"], fallback: 3),
                lighting: doubleValue(data["lighting"], fallback: 3),
                safety: doubleValue(data["safety"], fallback: 3),
                timestamp: timestamp
            )
        }
    }

    func fetchSafetySegments(limit: Int = 800) async throws -> [FSSegment] {
        let snapshot = try await db.collection("segments")
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.map { document in
            let data = document.data()
            return FSSegment(
                id: document.documentID,
                from: stringValue(data["from"]),
                to: stringValue(data["to"]),
                line: stringValue(data["line"]),
                reportsCount: intValue(data["reports_count"]) ?? 0,
                riskScore: doubleValue(data["risk_score"], fallback: 0.5),
                safetyLabel: stringValue(data["safety_label"], fallback: "C"),
                transportType: stringValue(data["transport_type"], fallback: "metro")
            )
        }
    }

    func fetchSafetyStations(limit: Int = 800) async throws -> [FSStation] {
        let snapshot = try await db.collection("stations")
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.map { document in
            let data = document.data()
            return FSStation(
                id: document.documentID,
                name: stringValue(data["name"], fallback: document.documentID),
                line: stringValue(data["line"]),
                type: stringValue(data["type"]),
                lat: doubleValue(data["lat"], fallback: 19.4326),
                lng: doubleValue(data["lng"], fallback: -99.1332)
            )
        }
    }

    private func stringValue(_ value: Any?, fallback: String = "") -> String {
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

    private func timestampValue(_ value: Any?) -> Timestamp? {
        if let timestamp = value as? Timestamp { return timestamp }
        if let date = value as? Date { return Timestamp(date: date) }
        return nil
    }
}
