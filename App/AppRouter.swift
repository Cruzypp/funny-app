import SwiftUI
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
    var night: Bool = true
    var vocab: SafetyVocab = .colors

    func go(_ s: AppScreen) {
        withAnimation(.easeInOut(duration: 0.26)) { screen = s }
    }
}
