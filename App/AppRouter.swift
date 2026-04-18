import SwiftUI
import MapKit
import Observation

// MARK: - Safety vocabulary (three display modes)
enum SafetyLevel { case high, medium, low }

enum SafetyVocab: String, CaseIterable {
    case colors, score, grade

    var label: String {
        switch self {
        case .colors: "Colores"
        case .score:  "Puntaje"
        case .grade:  "Letra"
        }
    }

    func badge(_ level: SafetyLevel) -> (tag: String, color: Color, tint: Color) {
        switch (self, level) {
        case (.colors, .high):   ("Segura", T.safe, T.safeTint)
        case (.colors, .medium): ("Media",  T.warn, T.warnTint)
        case (.colors, .low):    ("Riesgo", T.risk, T.riskTint)
        case (.score,  .high):   ("86",     T.safe, T.safeTint)
        case (.score,  .medium): ("62",     T.warn, T.warnTint)
        case (.score,  .low):    ("34",     T.risk, T.riskTint)
        case (.grade,  .high):   ("A",      T.safe, T.safeTint)
        case (.grade,  .medium): ("C",      T.warn, T.warnTint)
        case (.grade,  .low):    ("E",      T.risk, T.riskTint)
        }
    }
}

// MARK: - Screen enum
enum AppScreen: Equatable {
    case home
    case results(dest: String)
    case detail(routeId: String)
    case nav
    case survey
    case impact
    case heatmap
}

// MARK: - Router (@Observable = Swift 5.9 / iOS 17+)
@MainActor
@Observable
final class AppRouter {
    var screen: AppScreen = .home
    var night: Bool = false
    var vocab: SafetyVocab = .colors
    let location = LocationManager()

    // Origin: nil = usar GPS actual
    var originCoordinate: CLLocationCoordinate2D? = nil
    var originName: String = "Mi ubicación actual"
    var originMapItem: MKMapItem? = nil
    
    // Destination
    var destCoordinate: CLLocationCoordinate2D? = nil
    var destName: String = ""
    var destMapItem: MKMapItem? = nil
    
    // Selected route from ScreenResults
    var selectedRoute: MKRoute? = nil
    var activeRouteContext: RouteReviewContext? = nil
    var lastImpactSummary: RouteImpactSummary? = nil

    var contacts: [TrustedContact] = []

    func go(_ s: AppScreen) {
        screen = s
    }

    func addContact(_ contact: TrustedContact) async {
        contacts.append(contact)
        
        // Save to Firebase in background
        Task {
            do {
                let userId = await FirebaseService.shared.currentUserId()
                try await FirebaseService.shared.saveTrustedContact(userId: userId, contact: contact)
            } catch {
                print("Error saving contact to Firebase: \(error.localizedDescription)")
                // Contact is still saved in memory, but log the error
            }
        }
    }

    func loadContacts() async {
        do {
            let userId = await FirebaseService.shared.currentUserId()
            let loadedContacts = try await FirebaseService.shared.fetchTrustedContacts(userId: userId)
            await MainActor.run {
                self.contacts = loadedContacts
            }
        } catch {
            print("Error loading contacts from Firebase: \(error.localizedDescription)")
        }
    }

    func setActiveRouteContext(_ context: RouteReviewContext) {
        activeRouteContext = context
    }
}
