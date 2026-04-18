import FirebaseFirestore
import Foundation
import CoreLocation

// MARK: - 1. Usuario
struct FSUser: Codable {
    @DocumentID var id: String?
    var nombre: String
    var contactosConfianza: [String]      // UIDs de contactos
    var preferencias: FSPreferencias
    var historialRutas: [String]          // IDs de rutas

    enum CodingKeys: String, CodingKey {
        case id, nombre
        case contactosConfianza = "contactos_confianza"
        case preferencias
        case historialRutas = "historial_rutas"
    }
}

struct FSPreferencias: Codable {
    var modoNoche: Bool
    var nivelRiesgoTolerado: String       // "alto" | "medio" | "bajo"

    enum CodingKeys: String, CodingKey {
        case modoNoche = "modo_noche"
        case nivelRiesgoTolerado = "nivel_riesgo_tolerado"
    }
}

// MARK: - 2. Ubicación en tiempo real
struct FSLocation: Codable {
    @DocumentID var id: String?
    var userId: String
    var latitud: Double
    var longitud: Double
    var timestamp: Timestamp
    var estado: EstadoRuta               // en_ruta | llego | detenido

    enum CodingKeys: String, CodingKey {
        case id
        case userId   = "user_id"
        case latitud, longitud, timestamp, estado
    }
}

enum EstadoRuta: String, Codable {
    case enRuta    = "en_ruta"
    case llego     = "llego"
    case detenido  = "detenido"
}

// MARK: - 3. Incidentes (crowdsourcing)
struct FSIncident: Codable, Identifiable {
    @DocumentID var id: String?
    var tipo: TipoIncidente
    var latitud: Double
    var longitud: Double
    var hora: Timestamp
    var usuarioId: String
    var confiabilidad: Int               // 1–5

    enum CodingKeys: String, CodingKey {
        case id, tipo, latitud, longitud, hora
        case usuarioId    = "usuario_id"
        case confiabilidad
    }
}

enum TipoIncidente: String, Codable, CaseIterable {
    case robo         = "robo"
    case acoso        = "acoso"
    case zonaOscura   = "zona_oscura"
    case accidente    = "accidente"
    case otro         = "otro"
}

// MARK: - 3b. Datos de seguridad para mapa de calor
struct FSReport: Identifiable, Equatable {
    var id: String
    var segmentId: String
    var transportType: String
    var hour: Int
    var crowd: Double
    var lighting: Double
    var safety: Double
    var lat: Double?
    var lng: Double?
    var timestamp: Timestamp?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

struct FSSegment: Identifiable, Equatable {
    var id: String
    var from: String
    var to: String
    var line: String
    var reportsCount: Int
    var riskScore: Double
    var safetyLabel: String
    var transportType: String
    var lat: Double?
    var lng: Double?

    var title: String { "\(from) - \(to)" }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

struct FSStation: Identifiable, Equatable {
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

struct FSHeatmapSnapshot {
    var reports: [FSReport]
    var segments: [FSSegment]
    var stations: [FSStation]
    var incidents: [FSIncident]

    static let empty = FSHeatmapSnapshot(reports: [], segments: [], stations: [], incidents: [])
}

// MARK: - 4. Rutas
struct FSRoute: Codable, Identifiable {
    @DocumentID var id: String?
    var origen: FSCoord
    var destino: FSCoord
    var rutaSugerida: [GeoPoint]         // GeoPoints — Firestore no admite arrays anidados
    var nivelRiesgo: String              // "alto" | "medio" | "bajo"
    var tiempoEstimado: Int              // minutos
    var userId: String
    var timestamp: Timestamp

    enum CodingKeys: String, CodingKey {
        case id, origen, destino
        case rutaSugerida   = "ruta_sugerida"
        case nivelRiesgo    = "nivel_riesgo"
        case tiempoEstimado = "tiempo_estimado"
        case userId         = "user_id"
        case timestamp
    }
}

struct FSCoord: Codable {
    var latitud: Double
    var longitud: Double
    var nombre: String
}

struct FSRouteReview: Codable, Identifiable {
    @DocumentID var id: String?
    var routeId: String?
    var routeKey: String
    var userId: String
    var originName: String
    var destinationName: String
    var routeLabel: String
    var transportModes: [String]
    var safetyScore: Int
    var lightingScore: Int?
    var tags: [String]
    var destinationLat: Double?
    var destinationLng: Double?
    var startedAt: Timestamp
    var submittedAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case routeId = "route_id"
        case routeKey = "route_key"
        case userId = "user_id"
        case originName = "origin_name"
        case destinationName = "destination_name"
        case routeLabel = "route_label"
        case transportModes = "transport_modes"
        case safetyScore = "safety_score"
        case lightingScore = "lighting_score"
        case tags
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
        case startedAt = "started_at"
        case submittedAt = "submitted_at"
    }
}

// MARK: - 5. Alertas
struct FSAlert: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var tipo: TipoAlerta
    var timestamp: Timestamp
    var estado: EstadoAlerta
    var rutaId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tipo, timestamp, estado
        case rutaId = "ruta_id"
    }
}

enum TipoAlerta: String, Codable {
    case desvio     = "desvio"
    case emergencia = "emergencia"
    case llegada    = "llegada"
}

enum EstadoAlerta: String, Codable {
    case activa    = "activa"
    case resuelta  = "resuelta"
}
