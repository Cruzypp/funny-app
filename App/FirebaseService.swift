import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

// MARK: - Singleton de acceso a Firestore
@MainActor
final class FirebaseService {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()
    private let defaults = UserDefaults.standard
    private let installationIdKey = "caminos.installation_id"

    private init() {}

    // ─────────────────────────────────────
    // MARK: 0. Sesion / identidad
    // ─────────────────────────────────────

    func currentUserId() async -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        } catch {
            return localInstallationId()
        }
    }

    private func localInstallationId() -> String {
        if let existing = defaults.string(forKey: installationIdKey) {
            return existing
        }

        let generated = "local-\(UUID().uuidString.lowercased())"
        defaults.set(generated, forKey: installationIdKey)
        return generated
    }

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
    // MARK: 1.5 Contactos Confiables
    // ─────────────────────────────────────

    func saveTrustedContact(userId: String, contact: TrustedContact) async throws {
        let contactData: [String: Any] = [
            "id": contact.id.uuidString,
            "name": contact.name,
            "phone": contact.phone,
            "color": contact.color.description,
            "createdAt": Timestamp()
        ]
        try await db.collection("users").document(userId)
            .collection("trusted_contacts").document(contact.id.uuidString)
            .setData(contactData)
    }

    func fetchTrustedContacts(userId: String) async throws -> [TrustedContact] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("trusted_contacts").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let name = data["name"] as? String,
                  let phone = data["phone"] as? String,
                  let colorHex = data["color"] as? String else { return nil }
            
            let id = UUID(uuidString: doc.documentID) ?? UUID()
            let color = Color(hex: String(colorHex.dropFirst(6).dropLast(1))) // Parse hex from Color description
            return TrustedContact(id: id, name: name, phone: phone, color: color)
        }
    }

    func deleteTrustedContact(userId: String, contactId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("trusted_contacts").document(contactId).delete()
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

    /// Incidentes recientes cerca de una ubicación, filtrados localmente por radio.
    func fetchNearbyIncidents(
        lat: Double,
        lng: Double,
        radiusMeters: CLLocationDistance = 1400
    ) async throws -> [FSIncident] {
        let since = Timestamp(date: Date().addingTimeInterval(-72 * 60 * 60))
        let snapshot = try await db.collection("incidents")
            .whereField("hora", isGreaterThan: since)
            .order(by: "hora", descending: true)
            .limit(to: 150)
            .getDocuments()

        let center = CLLocation(latitude: lat, longitude: lng)
        return snapshot.documents
            .compactMap { try? $0.data(as: FSIncident.self) }
            .filter { incident in
                let point = CLLocation(latitude: incident.latitud, longitude: incident.longitud)
                return center.distance(from: point) <= radiusMeters
            }
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

    func persistRouteContext(_ context: RouteReviewContext) async -> RouteReviewContext {
        guard context.routeId == nil else { return context }
        guard let firstPoint = context.path.first else { return context }

        let userId = await currentUserId()
        let destination = context.destinationCoordinate ?? context.path.last ?? firstPoint
        let route = FSRoute(
            origen: FSCoord(
                latitud: firstPoint.latitude,
                longitud: firstPoint.longitude,
                nombre: context.originName
            ),
            destino: FSCoord(
                latitud: destination.latitude,
                longitud: destination.longitude,
                nombre: context.destinationName
            ),
            rutaSugerida: context.path.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) },
            nivelRiesgo: "medio",
            tiempoEstimado: context.expectedMinutes,
            userId: userId,
            timestamp: Timestamp(date: context.startedAt)
        )

        do {
            var updated = context
            updated.routeId = try await saveRoute(route)
            return updated
        } catch {
            return context
        }
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

// MARK: - Encuesta post-viaje / reseñas
extension FirebaseService {
    func submitRouteReview(
        context: RouteReviewContext,
        safetyScore: Int,
        lightingScore: Int?,
        tags: Set<String>
    ) async throws -> RouteImpactSummary {
        let persistedContext = await persistRouteContext(context)
        let userId = await currentUserId()
        let previousReviews = (try? await fetchRouteReviews(routeKey: persistedContext.routeKey)) ?? []
        let previousAverage = averageScore(for: previousReviews, fallback: safetyScore)

        let destinationLat = persistedContext.destinationCoordinate?.latitude ?? persistedContext.path.last?.latitude
        let destinationLng = persistedContext.destinationCoordinate?.longitude ?? persistedContext.path.last?.longitude

        let review = FSRouteReview(
            routeId: persistedContext.routeId,
            routeKey: persistedContext.routeKey,
            userId: userId,
            originName: persistedContext.originName,
            destinationName: persistedContext.destinationName,
            routeLabel: persistedContext.routeLabel,
            transportModes: persistedContext.transportModes.map(\.rawValue),
            safetyScore: safetyScore,
            lightingScore: lightingScore,
            tags: Array(tags).sorted(),
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            startedAt: Timestamp(date: persistedContext.startedAt),
            submittedAt: Timestamp(date: Date())
        )

        try db.collection("route_reviews").addDocument(from: review)

        if let incident = incidentFromReview(review) {
            try? await reportIncident(incident)
        }

        let updatedReviews = previousReviews + [review]
        let currentAverage = averageScore(for: updatedReviews, fallback: safetyScore)
        let userReviews = (try? await fetchUserRouteReviews(userId: userId)) ?? updatedReviews.filter { $0.userId == userId }

        try? await updateRouteRisk(routeId: persistedContext.routeId, averageSafety: currentAverage)

        return RouteImpactSummary(
            routeTitle: persistedContext.destinationName,
            routeLabel: routeDangerLabel(forAverageSafety: currentAverage),
            previousAverage: previousAverage,
            currentAverage: currentAverage,
            totalReviews: updatedReviews.count,
            myReviewsThisMonth: reviewsThisMonth(userReviews),
            reportedTags: tagLabels(for: review.tags),
            communityTags: topTagLabels(from: updatedReviews),
            submittedAt: review.submittedAt.dateValue(),
            submittedSafetyScore: safetyScore,
            submittedLightingScore: lightingScore,
            transportModes: persistedContext.transportModes,
            savedRemotely: true
        )
    }

    /// Mantiene compatibilidad con el flujo viejo.
    func submitSurveyReport(
        userId: String,
        lat: Double,
        lng: Double,
        safetyScore: Int,
        lightingScore: Int,
        tags: Set<String>,
        comment: String
    ) async throws {
        let tipo: TipoIncidente = tags.contains("harassment") ? .acoso
            : tags.contains("dark") ? .zonaOscura
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

    private func fetchRouteReviews(routeKey: String) async throws -> [FSRouteReview] {
        let snapshot = try await db.collection("route_reviews")
            .whereField("route_key", isEqualTo: routeKey)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: FSRouteReview.self) }
            .sorted { $0.submittedAt.dateValue() > $1.submittedAt.dateValue() }
    }

    private func fetchUserRouteReviews(userId: String) async throws -> [FSRouteReview] {
        let snapshot = try await db.collection("route_reviews")
            .whereField("user_id", isEqualTo: userId)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: FSRouteReview.self) }
    }

    private func reviewsThisMonth(_ reviews: [FSRouteReview]) -> Int {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date.distantPast
        return reviews.filter { $0.submittedAt.dateValue() >= monthStart }.count
    }

    private func averageScore(for reviews: [FSRouteReview], fallback: Int) -> Int {
        guard !reviews.isEmpty else { return fallback }
        let total = reviews.reduce(0) { $0 + $1.safetyScore }
        return Int((Double(total) / Double(reviews.count)).rounded())
    }

    private func updateRouteRisk(routeId: String?, averageSafety: Int) async throws {
        guard let routeId, !routeId.isEmpty else { return }

        try await db.collection("routes")
            .document(routeId)
            .updateData(["nivel_riesgo": routeDangerStorageValue(forAverageSafety: averageSafety)])
    }

    private func topTagLabels(from reviews: [FSRouteReview]) -> [String] {
        var counts: [String: Int] = [:]

        for tag in reviews.flatMap(\.tags) {
            counts[tag, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(3)
            .map { tagLabel(for: $0.key) }
    }

    private func tagLabels(for tags: [String]) -> [String] {
        tags.map(tagLabel(for:))
    }

    private func tagLabel(for tag: String) -> String {
        switch tag {
        case "people": return "Habia gente"
        case "alone": return "Zona sola"
        case "well-lit": return "Bien iluminada"
        case "dark": return "Poca luz"
        case "police": return "Vigilancia"
        case "construction": return "Obras"
        case "smooth": return "Banquetas buenas"
        case "harassment": return "Acoso"
        default: return tag.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func incidentFromReview(_ review: FSRouteReview) -> FSIncident? {
        guard let lat = review.destinationLat, let lng = review.destinationLng else { return nil }

        let tipo: TipoIncidente?
        if review.tags.contains("harassment") {
            tipo = .acoso
        } else if review.tags.contains("dark") || (review.lightingScore ?? 5) <= 2 {
            tipo = .zonaOscura
        } else if review.safetyScore <= 2 {
            tipo = .otro
        } else {
            tipo = nil
        }

        guard let tipo else { return nil }

        return FSIncident(
            tipo: tipo,
            latitud: lat,
            longitud: lng,
            hora: review.submittedAt,
            usuarioId: review.userId,
            confiabilidad: review.safetyScore
        )
    }
}
