import SwiftUI
import MapKit

// MARK: - Main screen
struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router
    @State private var timeFilter: TimeFilter = .night
    @State private var modeFilter: ModeFilter = .all
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 19.4300, longitude: -99.1332),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        )
    )

    private var night: Bool { router.night }

    var body: some View {
        VStack(spacing: 0) {
            HeatmapHeader(night: night, onBack: { router.go(.home) })

            ScrollView {
                VStack(spacing: 0) {
                    HeatmapMapSection(
                        night: night,
                        timeFilter: timeFilter,
                        cameraPosition: $cameraPosition
                    )
                    HeatmapFilters(night: night,
                                   timeFilter: $timeFilter,
                                   modeFilter: $modeFilter)
                    HeatmapInsightCard(night: night)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(T.bg(night))
    }
}

// MARK: - Filter enums
enum TimeFilter: String, CaseIterable {
    case morning   = "morning"
    case afternoon = "afternoon"
    case night     = "night"

    var label: String {
        switch self { case .morning: "6–12h"; case .afternoon: "12–19h"; case .night: "19–6h" }
    }
    var icon: String {
        switch self { case .morning, .afternoon: "sun.max.fill"; case .night: "moon.fill" }
    }

    // Real CDMX neighborhood coordinates with radius in meters
    var zones: [HeatZone] {
        switch self {
        case .morning:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4450, longitude: -99.1240), radius: 600, level: .high,   opacity: 0.35),  // Tepito
                .init(center: CLLocationCoordinate2D(latitude: 19.4220, longitude: -99.1200), radius: 700, level: .high,   opacity: 0.30),  // La Merced
                .init(center: CLLocationCoordinate2D(latitude: 19.4320, longitude: -99.1470), radius: 500, level: .medium, opacity: 0.30),  // Guerrero
            ]
        case .afternoon:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4450, longitude: -99.1240), radius: 600, level: .high,   opacity: 0.30),
                .init(center: CLLocationCoordinate2D(latitude: 19.4220, longitude: -99.1200), radius: 700, level: .high,   opacity: 0.35),
                .init(center: CLLocationCoordinate2D(latitude: 19.4320, longitude: -99.1470), radius: 500, level: .medium, opacity: 0.35),
                .init(center: CLLocationCoordinate2D(latitude: 19.4150, longitude: -99.1480), radius: 450, level: .medium, opacity: 0.30),  // Doctores
            ]
        case .night:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4450, longitude: -99.1240), radius: 700, level: .low,    opacity: 0.45),
                .init(center: CLLocationCoordinate2D(latitude: 19.4220, longitude: -99.1200), radius: 800, level: .low,    opacity: 0.50),
                .init(center: CLLocationCoordinate2D(latitude: 19.4320, longitude: -99.1470), radius: 550, level: .medium, opacity: 0.40),
                .init(center: CLLocationCoordinate2D(latitude: 19.4150, longitude: -99.1480), radius: 500, level: .low,    opacity: 0.40),  // Doctores
                .init(center: CLLocationCoordinate2D(latitude: 19.4100, longitude: -99.1650), radius: 400, level: .medium, opacity: 0.35),  // Roma/Condesa
            ]
        }
    }
}

struct HeatZone: Identifiable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let level: SafetyLevel
    let opacity: Double

    var color: Color {
        switch level {
        case .high:   return T.safe
        case .medium: return T.warn
        case .low:    return T.risk
        }
    }
}

enum ModeFilter: String, CaseIterable {
    case all, walk, metro, bus
    var label: String {
        switch self { case .all: "Todos"; case .walk: "Caminar"; case .metro: "Metro"; case .bus: "Bus" }
    }
    var icon: String? {
        switch self { case .all: nil; case .walk: "figure.walk"; case .metro: "tram.fill"; case .bus: "bus.fill" }
    }
}

// MARK: - Header
private struct HeatmapHeader: View {
    var night: Bool
    var onBack: () -> Void

    var body: some View {
        ScreenHeader(
            supertitle: "Comunidad",
            title: "Mapa de zonas",
            night: night,
            onBack: onBack,
            trailing: AnyView(
                Text("2,089 reportes")
                    .font(.mono(11)).tracking(0.3)
                    .foregroundStyle(T.sec(night))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                                in: Capsule())
            )
        )
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 12)
        .background(T.bg(night))
    }
}

// MARK: - Map + legend
private struct HeatmapMapSection: View {
    var night: Bool
    var timeFilter: TimeFilter
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $cameraPosition) {
                ForEach(timeFilter.zones) { zone in
                    MapCircle(center: zone.center, radius: zone.radius)
                        .foregroundStyle(zone.color.opacity(zone.opacity))
                        .stroke(zone.color.opacity(zone.opacity + 0.15), lineWidth: 1)
                }
                UserAnnotation()
            }
            .mapStyle(night
                ? .standard(pointsOfInterest: .excludingAll)
                : .standard(pointsOfInterest: .excludingAll)
            )
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 360)

            HeatmapLegend(night: night)
                .padding(.leading, 14)
                .padding(.bottom, 14)
        }
    }
}

private struct HeatmapLegend: View {
    var night: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Percepción")
                .font(.mono(10)).tracking(0.5)
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)
            legendRow("Segura", color: T.safe)
            legendRow("Media",  color: T.warn)
            legendRow("Riesgo", color: T.risk)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .caminosCard()
    }

    private func legendRow(_ label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).opacity(0.85).frame(width: 12, height: 12)
            Text(label).font(.system(size: 12)).foregroundStyle(T.pri(night))
        }
    }
}

// MARK: - Filters
private struct HeatmapFilters: View {
    var night: Bool
    @Binding var timeFilter: TimeFilter
    @Binding var modeFilter: ModeFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterLabel("Hora del día")
            timeButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func filterLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(11)).tracking(1)
            .foregroundStyle(T.sec(night))
            .textCase(.uppercase)
    }

    private var timeButtons: some View {
        HStack(spacing: 8) {
            ForEach(TimeFilter.allCases, id: \.rawValue) { f in
                TimeFilterButton(filter: f, selected: timeFilter, night: night) {
                    withAnimation(.easeInOut(duration: 0.2)) { timeFilter = f }
                }
            }
        }
    }
}

private struct TimeFilterButton: View {
    var filter: TimeFilter
    var selected: TimeFilter
    var night: Bool
    var action: () -> Void

    private var on: Bool { filter == selected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon).font(.system(size: 13))
                Text(filter.label).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(on ? T.bg(night) : T.pri(night))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(on ? T.pri(night) : (night ? Color.white.opacity(0.04) : Color.black.opacity(0.04)),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct ModeFilterButton: View {
    var filter: ModeFilter
    var selected: ModeFilter
    var night: Bool
    var action: () -> Void

    private var on: Bool { filter == selected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = filter.icon {
                    Image(systemName: icon).font(.system(size: 12))
                }
                Text(filter.label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(on ? T.bg(night) : T.pri(night))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(on ? T.pri(night) : Color.clear, in: Capsule())
            .overlay(
                Capsule().stroke(
                    on ? Color.clear : (night ? Color.white.opacity(0.10) : Color.black.opacity(0.14)),
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight card
private struct HeatmapInsightCard: View {
    var night: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(T.warnTint)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(T.warn)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Álvaro Obregón · Sonora")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Text("312 reportes · caminar · 22–02h · percepción bajó 8 pts esta semana.")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(T.sec(night))
        }
        .padding(16)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 20))
        .caminosCard()
    }
}

#Preview {
    ScreenHeatmap().environment(AppRouter())
}
