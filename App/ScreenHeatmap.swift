<<<<<<< Updated upstream
=======
import MapKit
>>>>>>> Stashed changes
import SwiftUI

struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router

<<<<<<< Updated upstream
    @State private var timeFilter = "night"
    @State private var modeFilter = "all"
    @State private var store = SafetyHeatmapStore()
=======
    @State private var store = HeatmapStore()
    @State private var timeFilter: TimeFilter = .night
    @State private var modeFilter: ModeFilter = .all
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 19.4300, longitude: -99.1332),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        )
    )
>>>>>>> Stashed changes

    private var night: Bool { router.night }
    private var zones: [HeatZone] { store.zones(timeFilter: timeFilter, modeFilter: modeFilter) }
    private var topZone: HeatZone? { store.topZone(timeFilter: timeFilter, modeFilter: modeFilter) }

    private var selectedTimeFilter: SafetyTimeFilter {
        SafetyTimeFilter(rawValue: timeFilter) ?? .night
    }

    private var selectedTransportFilter: TransportFilter {
        TransportFilter(rawValue: modeFilter) ?? .all
    }

    private var zones: [SafetyZonePrediction] {
        store.zones(timeFilter: selectedTimeFilter, transportFilter: selectedTransportFilter)
    }

    var body: some View {
        VStack(spacing: 0) {
<<<<<<< Updated upstream
            // Sticky header
            ScreenHeader(supertitle: "Comunidad", title: "Mapa de zonas", night: night,
                         onBack: { router.go(.home) },
                         trailing: AnyView(headerCounter))
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 12)
            .background(T.bg(night))

            ScrollView {
                VStack(spacing: 0) {
                    // Map with heatmap
                    mapSection

                    // Filters
                    filtersSection

                    // Insight card
                    insightCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
=======
            HeatmapHeader(
                night: night,
                reportCount: store.signalCount,
                isLoading: store.isLoading,
                onBack: { router.go(.home) }
            )

            ScrollView {
                VStack(spacing: 0) {
                    HeatmapMapSection(
                        night: night,
                        zones: zones,
                        cameraPosition: $cameraPosition
                    )

                    HeatmapFilters(
                        night: night,
                        timeFilter: $timeFilter,
                        modeFilter: $modeFilter
                    )

                    HeatmapInsightCard(
                        night: night,
                        zone: topZone,
                        isLoading: store.isLoading,
                        errorMessage: store.errorMessage
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
        }
    }

    private var headerCounter: some View {
        HStack(spacing: 6) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(T.sec(night))
            }

            Text("\(store.reportCount.formatted()) reportes")
                .font(.mono(11)).tracking(0.3)
                .foregroundStyle(T.sec(night))
=======
        }
    }
}

// MARK: - Filter enums
enum TimeFilter: String, CaseIterable {
    case morning = "morning"
    case afternoon = "afternoon"
    case night = "night"

    var label: String {
        switch self {
        case .morning: "6-12h"
        case .afternoon: "12-19h"
        case .night: "19-6h"
        }
    }

    var icon: String {
        switch self {
        case .morning, .afternoon: "sun.max.fill"
        case .night: "moon.fill"
        }
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

// MARK: - Header
private struct HeatmapHeader: View {
    var night: Bool
    var reportCount: Int
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

            Text("\(reportCount.formatted()) señales")
                .font(.mono(11)).tracking(0.3)
                .foregroundStyle(T.sec(night))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                    in: Capsule())
    }
}

// MARK: - Map + legend
private struct HeatmapMapSection: View {
    var night: Bool
    var zones: [HeatZone]
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $cameraPosition) {
                ForEach(zones) { zone in
                    MapCircle(center: zone.center, radius: zone.radius)
                        .foregroundStyle(zone.color.opacity(zone.opacity))
                        .stroke(zone.color.opacity(0.56), lineWidth: zone.level == .low ? 1.4 : 1)
                }

                ForEach(Array(zones.prefix(9))) { zone in
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
>>>>>>> Stashed changes
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                    in: Capsule())
    }

    // MARK: Map
    private var mapSection: some View {
        ZStack(alignment: .bottomLeading) {
            SafetyHeatmapMap(zones: zones, night: night)
                .overlay(alignment: .topTrailing) {
                    sourcePill
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }

            if zones.isEmpty {
                noDataOverlay
                    .padding(.horizontal, 20)
            }

            // Legend overlay
            VStack(alignment: .leading, spacing: 6) {
                Text("Percepción")
                    .font(.mono(10)).tracking(0.5)
                    .foregroundStyle(T.sec(night))
                    .textCase(.uppercase)

                ForEach([("Segura", T.safe), ("Media", T.warn), ("Riesgo", T.risk)], id: \.0) { item in
                    HStack(spacing: 8) {
                        Circle().fill(item.1).opacity(0.85).frame(width: 12, height: 12)
                        Text(item.0)
                            .font(.system(size: 12))
                            .foregroundStyle(T.pri(night))
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .caminosCard()
            .padding(.leading, 14)
            .padding(.bottom, 14)
        }
    }

    private var sourcePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .semibold))
            Text("Core ML")
            Text("·")
                .opacity(0.55)
            Text(store.sourceLabel)
        }
        .font(.mono(10)).tracking(0.3)
        .foregroundStyle(T.pri(night))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .caminosCard()
    }

    private var noDataOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(T.warn)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sin zonas para este filtro")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Text("Prueba otro horario o transporte.")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .caminosCard()
    }

    // MARK: Filters
    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
<<<<<<< Updated upstream
            // Time of day
            VStack(alignment: .leading, spacing: 10) {
                Text("Hora del día")
                    .font(.mono(11)).tracking(1)
                    .foregroundStyle(T.sec(night))
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    ForEach([
                        ("morning",   "6–12h",   "sun.max.fill"),
                        ("afternoon", "12–19h",  "sun.max.fill"),
                        ("night",     "19–6h",   "moon.fill"),
                    ], id: \.0) { id, label, icon in
                        let on = timeFilter == id
                        Button { withAnimation(.easeInOut(duration: 0.2)) { timeFilter = id } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon).font(.system(size: 13))
                                Text(label).font(.system(size: 13, weight: .medium))
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
            }

            // Transport mode
            VStack(alignment: .leading, spacing: 10) {
                Text("Transporte")
                    .font(.mono(11)).tracking(1)
                    .foregroundStyle(T.sec(night))
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    ForEach([
                        ("all",   "Todos",   nil as String?),
                        ("walk",  "Caminar", "figure.walk"),
                        ("metro", "Metro",   "tram.fill"),
                        ("bus",   "Bus",     "bus.fill"),
                    ], id: \.0) { id, label, icon in
                        let on = modeFilter == id
                        Button { withAnimation(.easeInOut(duration: 0.2)) { modeFilter = id } } label: {
                            HStack(spacing: 4) {
                                if let icon { Image(systemName: icon).font(.system(size: 12)) }
                                Text(label).font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(on ? T.bg(night) : T.pri(night))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(
                                Capsule().stroke(
                                    on ? Color.clear : (night ? Color.white.opacity(0.10) : Color.black.opacity(0.14)),
                                    lineWidth: 1.5
                                )
                            )
                            .background(on ? T.pri(night) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
=======
            filterLabel("Hora del día")
            timeButtons

            filterLabel("Transporte")
                .padding(.top, 4)
            modeButtons
>>>>>>> Stashed changes
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: Insight card
    @ViewBuilder
    private var insightCard: some View {
        if let insight = store.topInsight(timeFilter: selectedTimeFilter, transportFilter: selectedTransportFilter) {
            insightCard(for: insight)
        } else {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(T.warnTint)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(T.warn)
                    )

<<<<<<< Updated upstream
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sin lectura suficiente")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                    Text(store.errorMessage ?? "Aún no hay reportes para ese filtro.")
                        .font(.system(size: 12))
                        .foregroundStyle(T.sec(night))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
=======
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
>>>>>>> Stashed changes
                }
            }
            .padding(16)
            .background(T.surface(night), in: RoundedRectangle(cornerRadius: 20))
            .caminosCard()
        }
    }

<<<<<<< Updated upstream
    private func insightCard(for zone: SafetyZonePrediction) -> some View {
        let color = zone.level.heatColor
        let tint = zone.level == .high ? T.safeTint : zone.level == .medium ? T.warnTint : T.riskTint
        let icon = zone.level == .high ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(zone.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                        .lineLimit(2)
                    SafetyBadge(level: zone.level, vocab: router.vocab, size: .sm)
                }

                Text("\(zone.summary) - confianza \(Int((zone.confidence * 100).rounded()))%.")
=======
private struct HeatmapFilterButton: View {
    var label: String
    var icon: String?
    var selected: Bool
    var night: Bool
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 12 : 13))
                }
                Text(label)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
            }
            .foregroundStyle(selected ? T.bg(night) : T.pri(night))
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 44 : 54)
            .background(selected ? T.pri(night) : Color.clear,
                        in: RoundedRectangle(cornerRadius: compact ? 999 : 16))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 999 : 16)
                    .stroke(selected ? Color.clear : (night ? Color.white.opacity(0.10) : Color.black.opacity(0.14)),
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight card
private struct HeatmapInsightCard: View {
    var night: Bool
    var zone: HeatZone?
    var isLoading: Bool
    var errorMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBox

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                    .lineLimit(2)

                Text(subtitle)
>>>>>>> Stashed changes
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let zone {
                SafetyBadge(level: zone.level, vocab: .colors, size: .sm)
            }
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
        return errorMessage ?? "Cuando lleguen reportes nuevos, el mapa se actualiza aquí."
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
    let r = AppRouter()
    return ScreenHeatmap().environment(r)
}
