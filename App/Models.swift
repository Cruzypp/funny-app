import SwiftUI

// MARK: - Map primitives
struct MapRoute {
    var id: String
    var color: Color
    var isActive: Bool = false
    var isDashed: Bool = false
    /// Points in the 402×designHeight design coordinate space
    var points: [CGPoint]
}

struct MapMarker {
    var point: CGPoint
    enum Kind { case origin, dest }
    var kind: Kind
}

struct HeatmapBlob {
    var center: CGPoint
    var radius: CGFloat
    var level: SafetyLevel
    var opacity: CGFloat = 0.35

    var color: Color {
        switch level {
        case .high:   T.safe
        case .medium: T.warn
        case .low:    T.risk
        }
    }
}

// MARK: - Route / transit models
enum TransitMode: String {
    case walk, metro, bus
    var sfSymbol: String {
        switch self {
        case .walk:  "figure.walk"
        case .metro: "tram.fill"
        case .bus:   "bus.fill"
        }
    }
}

struct RouteOption: Identifiable {
    var id: String
    var label: String
    var timeMinutes: Int
    var safety: SafetyLevel
    var transit: [TransitMode]
    var badge: String?
    var color: Color
    var detail: String
}

struct SegmentNote {
    var sfSymbol: String
    var text: String
    enum Tone { case positive, caution, risk }
    var tone: Tone

    var color: Color {
        switch tone { case .positive: T.safe; case .caution: T.warn; case .risk: T.risk }
    }
    var tint: Color {
        switch tone { case .positive: T.safeTint; case .caution: T.warnTint; case .risk: T.riskTint }
    }
}

struct RouteSegment {
    var sfSymbol: String
    var mode: String
    var duration: String
    var distance: String
    var from: String
    var to: String
    var safety: SafetyLevel
    var notes: [SegmentNote]
}

// MARK: - Home screen models
struct TrustedContact {
    var name: String
    var color: Color
}

struct RecentDestination: Identifiable {
    var id = UUID()
    var sfSymbol: String
    var title: String
    var subtitle: String
    var safety: SafetyLevel
}
