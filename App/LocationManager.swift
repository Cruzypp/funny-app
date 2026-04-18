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
    var mapItem: MKMapItem?
}

// MARK: - Location + search manager
@MainActor
@Observable
final class LocationManager: NSObject {
    private let manager = CLLocationManager()

    var userLocation: CLLocation?
    var isAuthorized = false
    var searchResults: [AddressResult] = []
    var isSearching = false

    // Ciudad de Mexico default region used for search bias
    static let defaultCityCenter = CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332)
    static let defaultCityRegion = MKCoordinateRegion(
        center: defaultCityCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
    )

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
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Apple Maps Search (MKLocalSearch)
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = LocationManager.defaultCityRegion // Prioriza resultados en CDMX

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            
            self.searchResults = response.mapItems.map { item in
                AddressResult(
                    title: item.name ?? "Sin nombre",
                    subtitle: item.placemark.title ?? "",
                    coordinate: item.placemark.coordinate,
                    mapItem: item
                )
            }
            isSearching = false
        } catch {
            print("Apple Maps Search Error: \(error)")
            searchResults = []
            isSearching = false
        }
    }

    func clearSearch() {
        searchResults = []
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
