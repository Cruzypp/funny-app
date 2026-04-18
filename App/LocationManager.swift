import Foundation
import CoreLocation
import MapKit
import Observation

// MARK: - Address search result
struct AddressResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D?
    let placeId: String?
}

// MARK: - Location + search manager
@MainActor
@Observable
final class LocationManager: NSObject {
    private let manager = CLLocationManager()
    private let googleApiKey = "TU_API_KEY_AQUI" // <--- PON TU API KEY DE GOOGLE AQUÍ

    var userLocation: CLLocation?
    var isAuthorized = false
    var searchResults: [AddressResult] = []
    var isSearching = false

    // CDMX default region used for search bias
    static let cdmxCenter = CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Google Places Search
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        let urlString = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=\(query)&key=\(googleApiKey)&components=country:mx&language=es"
        
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            isSearching = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(GooglePredictionsResponse.self, from: data)
            
            self.searchResults = response.predictions.map { pred in
                AddressResult(
                    title: pred.structuredFormatting.mainText,
                    subtitle: pred.structuredFormatting.secondaryText ?? "",
                    coordinate: nil, // Google Autocomplete no da coordenadas directamente, se necesita "Place Details" después
                    placeId: pred.placeId
                )
            }
            isSearching = false
        } catch {
            print("Google Places Error: \(error)")
            searchResults = []
            isSearching = false
        }
    }

    func clearSearch() {
        searchResults = []
    }
}

// MARK: - Google API Models
struct GooglePredictionsResponse: Codable {
    let predictions: [GooglePrediction]
    
    struct GooglePrediction: Codable {
        let placeId: String
        let structuredFormatting: StructuredFormatting
        
        enum CodingKeys: String, CodingKey {
            case placeId = "place_id"
            case structuredFormatting = "structured_formatting"
        }
    }
    
    struct StructuredFormatting: Codable {
        let mainText: String
        let secondaryText: String?
        
        enum CodingKeys: String, CodingKey {
            case mainText = "main_text"
            case secondaryText = "secondary_text"
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.userLocation = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.isAuthorized = true
                self.startTracking()
            default:
                self.isAuthorized = false
            }
        }
    }
}
