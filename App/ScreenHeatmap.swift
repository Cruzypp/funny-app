import MapKit
import SwiftUI

struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router

    @State private var store = HeatmapStore()
    @State private var timeFilter: TimeFilter = .all
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.defaultCityCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )


    private var night: Bool { router.night }
    private var zones: [HeatZone] { store.zones(timeFilter: timeFilter, modeFilter: .all) }

    var body: some View {
        VStack(spacing: 0) {
            HeatmapHeader(
                night: night,
                signalCount: store.signalCount,
                isLoading: store.isLoading,
                onBack: { router.go(.home) }
            )

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    HeatmapMapSection(
                        night: night,
                        zones: zones,
                        sourceLabel: store.sourceLabel,
                        coverageLabel: "\(store.snapshot.reports.count.formatted()) rep · \(zones.count.formatted()) zonas",
                        cameraPosition: $cameraPosition
                    )
                    .frame(height: max(360, proxy.size.height - 50))

                    HeatmapTimeFilters(
                        night: night,
                        timeFilter: $timeFilter
                    )
                    .padding(.bottom, 6)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .background(T.bg(night))
        .task {
            await store.load()
        }
    }
}

enum TimeFilter: String, CaseIterable {
    case all = "all"
    case morning = "morning"
    case afternoon = "afternoon"
    case night = "night"

    var label: String {
        switch self { case .all: "Todo"; case .morning: "6–12h"; case .afternoon: "12–19h"; case .night: "19–6h" }
    }
    var icon: String {
        switch self { case .all: "map.fill"; case .morning, .afternoon: "sun.max.fill"; case .night: "moon.fill" }
    }
}

enum ModeFilter: String, CaseIterable {
    case all
    case walk

    var label: String {
        switch self {
        case .all: "Todos"
        case .walk: "Caminar"
        }
    }

    var icon: String? {
        switch self {
        case .all: nil
        case .walk: "figure.walk"
        }
    }
}

private struct HeatmapHeader: View {
    var night: Bool
    var signalCount: Int
    var isLoading: Bool
    var onBack: () -> Void

    var body: some View {
        ScreenHeader(
            supertitle: "Comunidad",
            title: "Mapa de zonas",
            night: night,
            onBack: onBack,
            trailing: AnyView(counter)
        )
        .padding(.horizontal, 16)
        .padding(.top, 42)
        .padding(.bottom, 6)
        .background(T.bg(night))
    }

    private var counter: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(T.sec(night))
            }

            Text("\(signalCount.formatted()) señales")
                .font(.mono(11)).tracking(0.3)
                .foregroundStyle(T.sec(night))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                    in: Capsule())
    }
}

private struct HeatmapMapSection: View {
    var night: Bool
    var zones: [HeatZone]
    var sourceLabel: String
    var coverageLabel: String
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $cameraPosition) {
                ForEach(zones) { zone in
                    MapCircle(center: zone.center, radius: zone.radius)
                        .foregroundStyle(zone.color.opacity(zone.opacity))
                        .stroke(zone.color.opacity(0.56), lineWidth: zone.level == .low ? 1.4 : 1)
                }

                ForEach(Array(zones.dropFirst(12).prefix(260))) { zone in
                    Annotation("", coordinate: zone.center) {
                        HeatmapDot(zone: zone)
                    }
                }

                ForEach(Array(zones.prefix(12))) { zone in
                    Annotation("", coordinate: zone.center) {
                        HeatmapPin(zone: zone, night: night)
                    }
                }

                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: zoneSignature) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    cameraPosition = .region(Self.region(for: zones))
                }
            }

            if zones.isEmpty {
                HeatmapEmptyState(night: night)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HeatmapLegend(night: night)
                .padding(.leading, 14)
                .padding(.bottom, 14)

            HeatmapSourcePill(night: night, sourceLabel: sourceLabel, coverageLabel: coverageLabel)
                .padding(.top, 14)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var zoneSignature: String {
        zones.map { "\($0.id):\($0.scoreLabel)" }.joined(separator: "|")
    }

    private static func region(for zones: [HeatZone]) -> MKCoordinateRegion {
        guard !zones.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
                span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
            )
        }

        let coordinates = zones.map(\.center)
        let minLat = coordinates.map(\.latitude).min() ?? 19.4326
        let maxLat = coordinates.map(\.latitude).max() ?? 19.4326
        let minLng = coordinates.map(\.longitude).min() ?? -99.1332
        let maxLng = coordinates.map(\.longitude).max() ?? -99.1332

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.025, (maxLat - minLat) * 1.65),
                longitudeDelta: max(0.025, (maxLng - minLng) * 1.65)
            )
        )
    }
}

private struct HeatmapDot: View {
    var zone: HeatZone

    var body: some View {
        Circle()
            .fill(zone.color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
            .shadow(color: zone.color.opacity(0.32), radius: 5)
    }
}

private struct HeatmapPin: View {
    var zone: HeatZone
    var night: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(zone.scoreLabel)
                .font(.mono(10))
                .fontWeight(.bold)
                .foregroundStyle(T.pri(night))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())

            Circle()
                .fill(zone.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
        }
        .shadow(color: zone.color.opacity(0.35), radius: 8)
    }
}

private struct HeatmapSourcePill: View {
    var night: Bool
    var sourceLabel: String
    var coverageLabel: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .semibold))
                Text(sourceLabel)
            }

            Text(coverageLabel)
                .foregroundStyle(T.sec(night))
        }
        .font(.mono(10)).tracking(0.3)
        .foregroundStyle(T.pri(night))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .caminosCard()
    }
}

private struct HeatmapEmptyState: View {
    var night: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.warn)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sin zonas disponibles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Text("Aún no hay datos mapeables.")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .caminosCard()
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
            legendRow("Media", color: T.warn)
            legendRow("Riesgo", color: T.risk)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .caminosCard()
    }

    private func legendRow(_ label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .opacity(0.85)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(T.pri(night))
        }
    }
}

private struct HeatmapTimeFilters: View {
    var night: Bool
    @Binding var timeFilter: TimeFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TimeFilter.allCases, id: \.rawValue) { filter in
                HeatmapTimeButton(
                    label: filter.label,
                    icon: filter.icon,
                    selected: filter == timeFilter,
                    night: night
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        timeFilter = filter
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct HeatmapTimeButton: View {
    var label: String
    var icon: String
    var selected: Bool
    var night: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(selected ? T.cream : T.pri(night))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(selected ? T.ink : inactiveBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inactiveBackground: Color {
        night ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
}

#Preview {
    ScreenHeatmap().environment(AppRouter())
}
