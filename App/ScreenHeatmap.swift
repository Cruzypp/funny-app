import SwiftUI

struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router

    @State private var timeFilter = "night"
    @State private var modeFilter = "all"
    @State private var store = SafetyHeatmapStore()

    private var night: Bool { router.night }

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

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sin lectura suficiente")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                    Text(store.errorMessage ?? "Aún no hay reportes para ese filtro.")
                        .font(.system(size: 12))
                        .foregroundStyle(T.sec(night))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(T.surface(night), in: RoundedRectangle(cornerRadius: 20))
            .caminosCard()
        }
    }

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
    let r = AppRouter()
    return ScreenHeatmap().environment(r)
}
