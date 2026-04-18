import SwiftUI
import MapKit
import FirebaseFirestore

// MARK: - Main screen
struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router
    @State private var timeFilter: TimeFilter = .night
    @State private var modeFilter: ModeFilter = .all
    @State private var reportCount: Int = 0
    @State private var isLoading = true
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.defaultCityCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )

    private var night: Bool { router.night }

    var body: some View {
        VStack(spacing: 0) {
            HeatmapHeader(night: night, reportCount: reportCount, onBack: { router.go(.home) })

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
                    HeatmapInsightCard(night: night, reportCount: reportCount)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(T.bg(night))
        .task {
            await loadRealData()
        }
    }
    
    private func loadRealData() async {
        isLoading = true
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("route_reviews").getDocuments()
            self.reportCount = snapshot.count
        } catch {
            print("Error fetching reports: \(error)")
            self.reportCount = 0
        }
        isLoading = false
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

    var zones: [HeatZone] {
        switch self {
        case .morning:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332), radius: 700, level: .high,   opacity: 0.35),
                .init(center: CLLocationCoordinate2D(latitude: 19.4236, longitude: -99.1637), radius: 600, level: .high,   opacity: 0.30),
                .init(center: CLLocationCoordinate2D(latitude: 19.4114, longitude: -99.1716), radius: 500, level: .medium, opacity: 0.28),
            ]
        case .afternoon:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332), radius: 700, level: .high,   opacity: 0.30),
                .init(center: CLLocationCoordinate2D(latitude: 19.4236, longitude: -99.1637), radius: 600, level: .high,   opacity: 0.35),
                .init(center: CLLocationCoordinate2D(latitude: 19.4114, longitude: -99.1716), radius: 500, level: .medium, opacity: 0.30),
                .init(center: CLLocationCoordinate2D(latitude: 19.3494, longitude: -99.1617), radius: 450, level: .medium, opacity: 0.28),
            ]
        case .night:
            return [
                .init(center: CLLocationCoordinate2D(latitude: 19.4236, longitude: -99.1637), radius: 800, level: .low,    opacity: 0.50),
                .init(center: CLLocationCoordinate2D(latitude: 19.4114, longitude: -99.1716), radius: 700, level: .low,    opacity: 0.45),
                .init(center: CLLocationCoordinate2D(latitude: 19.4342, longitude: -99.2099), radius: 550, level: .low,    opacity: 0.40),
                .init(center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332), radius: 500, level: .medium, opacity: 0.35),
                .init(center: CLLocationCoordinate2D(latitude: 19.4200, longitude: -99.1700), radius: 400, level: .medium, opacity: 0.40),
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
    var reportCount: Int
    var onBack: () -> Void

    var body: some View {
        ScreenHeader(
            supertitle: "Comunidad",
            title: "Mapa de zonas",
            night: night,
            onBack: onBack,
            trailing: AnyView(
                Text("\(reportCount) reportes")
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

// MARK: - Insight card
private struct HeatmapInsightCard: View {
    var night: Bool
    var reportCount: Int

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
                Text("Ciudad de México")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Text("\(reportCount) reportes totales de la comunidad. Tu feedback está ayudando a mapear la seguridad en tiempo real.")
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
