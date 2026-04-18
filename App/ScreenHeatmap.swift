import MapKit
import SwiftUI

struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router

    @State private var store = HeatmapStore()
    @State private var timeFilter: TimeFilter = .night
    @State private var modeFilter: ModeFilter = .all
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.defaultCityCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )


    private var night: Bool { router.night }
    private var zones: [HeatZone] { store.zones(timeFilter: timeFilter, modeFilter: modeFilter) }
    private var topZone: HeatZone? { store.topZone(timeFilter: timeFilter, modeFilter: modeFilter) }

    var body: some View {
        VStack(spacing: 0) {
            HeatmapHeader(
                night: night,
                signalCount: store.signalCount,
                isLoading: store.isLoading,
                onBack: { router.go(.home) }
            )

            ScrollView {
                VStack(spacing: 0) {
                    HeatmapMapSection(
                        night: night,
                        zones: zones,
                        sourceLabel: store.sourceLabel,
                        coverageLabel: "\(store.snapshot.reports.count.formatted()) rep · \(zones.count.formatted()) zonas",
                        cameraPosition: $cameraPosition
                    )
                    HeatmapFilters(night: night,
                        timeFilter: $timeFilter,
                        modeFilter: $modeFilter)
                    HeatmapInsightCard(
                        night: night,
                        signalCount: store.signalCount,
                        zone: topZone,
                        isLoading: store.isLoading,
                        errorMessage: store.errorMessage,
                        vocab: router.vocab
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.load()
            }
        }
        .background(T.bg(night))
        .task {
            await store.load()
        }
    }
}

enum TimeFilter: String, CaseIterable {
    case morning = "morning"
    case afternoon = "afternoon"
    case night = "night"

    var label: String {
        switch self { case .morning: "6–12h"; case .afternoon: "12–19h"; case .night: "19–6h" }
    }
    var icon: String {
        switch self { case .morning, .afternoon: "sun.max.fill"; case .night: "moon.fill" }
    }
}

enum ModeFilter: String, CaseIterable {
    case all
    case walk
    case metro
    case bus

    var label: String {
        switch self {
        case .all: "Todos"
        case .walk: "Caminar"
        case .metro: "Metro"
        case .bus: "Bus"
        }
    }

    var icon: String? {
        switch self {
        case .all: nil
        case .walk: "figure.walk"
        case .metro: "tram.fill"
        case .bus: "bus.fill"
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
        .padding(.top, 58)
        .padding(.bottom, 12)
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
            .frame(height: 420)
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
                Text("Sin zonas para este filtro")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Text("Cambia la hora o el transporte.")
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

private struct HeatmapFilters: View {
    var night: Bool
    @Binding var timeFilter: TimeFilter
    @Binding var modeFilter: ModeFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterLabel("Hora del día")
            timeButtons

            filterLabel("Transporte")
                .padding(.top, 4)
            modeButtons
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
            ForEach(TimeFilter.allCases, id: \.rawValue) { filter in
                HeatmapFilterButton(
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
    }

    private var modeButtons: some View {
        HStack(spacing: 8) {
            ForEach(ModeFilter.allCases, id: \.rawValue) { filter in
                HeatmapFilterButton(
                    label: filter.label,
                    icon: filter.icon,
                    selected: filter == modeFilter,
                    night: night,
                    compact: true
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        modeFilter = filter
                    }
                }
            }
        }
    }
}

private struct HeatmapFilterButton: View {
    var label: String
    var icon: String?
    var selected: Bool
    var night: Bool
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 5 : 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                }

                Text(label)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, compact ? 8 : 10)
            .background(background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(border, lineWidth: selected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        selected ? T.cream : T.pri(night)
    }

    private var background: Color {
        if selected { return T.ink }
        return night ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    private var border: Color {
        selected ? T.ink.opacity(0.65) : T.sec(night).opacity(0.16)
    }
}

// MARK: - Insight card
private struct HeatmapInsightCard: View {
    var night: Bool
    var signalCount: Int
    var zone: HeatZone?
    var isLoading: Bool
    var errorMessage: String?
    var vocab: SafetyVocab

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBox

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                        .lineLimit(2)

                    if let zone {
                        SafetyBadge(level: zone.level, vocab: vocab, size: .sm)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 20))
        .caminosCard()
    }

    private var title: String {
        if let zone { return zone.title }
        return isLoading ? "Calculando zonas" : "Sin lectura suficiente"
    }

    private var subtitle: String {
        if let zone {
            return "\(zone.detail) - riesgo \(zone.scoreLabel)."
        }
        if let errorMessage {
            return errorMessage
        }
        return "\(signalCount.formatted()) reportes totales de la comunidad. Tu feedback está ayudando a mapear la seguridad en tiempo real."
    }

    private var iconBox: some View {
        let level = zone?.level ?? .medium
        let color = zone?.color ?? T.warn
        let tint = level == .high ? T.safeTint : level == .medium ? T.warnTint : T.riskTint
        let icon = level == .high ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"

        return RoundedRectangle(cornerRadius: 10)
            .fill(tint)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: isLoading ? "sparkle.magnifyingglass" : icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            )
    }
}

#Preview {
    ScreenHeatmap().environment(AppRouter())
}
