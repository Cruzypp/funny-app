import SwiftUI

struct ScreenHeatmap: View {
    @Environment(AppRouter.self) var router

    @State private var timeFilter = "night"
    @State private var modeFilter = "all"

    private var night: Bool { router.night }

    private let heatmapData: [String: [HeatmapBlob]] = [
        "morning": [
            .init(center: CGPoint(x: 90,  y: 180), radius: 55, level: .high,   opacity: 0.35),
            .init(center: CGPoint(x: 220, y: 300), radius: 60, level: .high,   opacity: 0.30),
            .init(center: CGPoint(x: 310, y: 120), radius: 45, level: .medium, opacity: 0.30),
        ],
        "afternoon": [
            .init(center: CGPoint(x: 90,  y: 180), radius: 55, level: .high,   opacity: 0.30),
            .init(center: CGPoint(x: 220, y: 300), radius: 60, level: .high,   opacity: 0.35),
            .init(center: CGPoint(x: 310, y: 120), radius: 45, level: .medium, opacity: 0.35),
            .init(center: CGPoint(x: 160, y: 420), radius: 40, level: .medium, opacity: 0.30),
        ],
        "night": [
            .init(center: CGPoint(x: 90,  y: 180), radius: 55, level: .medium, opacity: 0.40),
            .init(center: CGPoint(x: 220, y: 300), radius: 70, level: .low,    opacity: 0.45),
            .init(center: CGPoint(x: 310, y: 120), radius: 50, level: .low,    opacity: 0.40),
            .init(center: CGPoint(x: 160, y: 420), radius: 45, level: .low,    opacity: 0.40),
            .init(center: CGPoint(x: 280, y: 250), radius: 40, level: .medium, opacity: 0.35),
        ],
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Sticky header
            ScreenHeader(supertitle: "Comunidad", title: "Mapa de zonas", night: night,
                         onBack: { router.go(.home) },
                         trailing: AnyView(
                            Text("2,089 reportes")
                                .font(.mono(11)).tracking(0.3)
                                .foregroundStyle(T.sec(night))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                                            in: Capsule())
                         ))
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
        }
        .background(T.bg(night))
    }

    // MARK: Map
    private var mapSection: some View {
        ZStack(alignment: .bottomLeading) {
            CDMXMap(
                designHeight: 460,
                night: night,
                heatmap: heatmapData[timeFilter]
            )

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
    private var insightCard: some View {
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
    let r = AppRouter()
    return ScreenHeatmap().environment(r)
}
