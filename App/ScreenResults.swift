import SwiftUI

struct ScreenResults: View {
    @Environment(AppRouter.self) var router
    var dest: String

    @State private var selected = "safe"

    private var night: Bool { router.night }

    private let routes: [MapRoute] = [
        .init(id: "fast", color: Color(hex: "2563EB"), isActive: false,
              points: [[60,340],[60,250],[140,250],[140,160],[260,160],[260,80],[330,80]].map { CGPoint(x: $0[0], y: $0[1]) }),
        .init(id: "safe", color: T.safe, isActive: true,
              points: [[60,340],[150,340],[150,260],[220,260],[220,180],[290,180],[290,100],[330,100],[330,80]].map { CGPoint(x: $0[0], y: $0[1]) }),
    ]

    private var options: [RouteOption] {[
        .init(id: "fast",  label: "Ruta rápida",  timeMinutes: 18, safety: .medium,
              transit: [.walk, .metro], badge: "Más rápida",  color: Color(hex: "2563EB"),
              detail: "5 min caminando · 13 min Metro"),
        .init(id: "safe",  label: "Ruta segura",  timeMinutes: 24, safety: .high,
              transit: [.walk, .bus, .walk], badge: "Recomendada", color: T.safe,
              detail: "7 min caminando · 14 min Metrobús · 3 min caminando"),
        .init(id: "mixed", label: "Ruta mixta",   timeMinutes: 28, safety: .medium,
              transit: [.walk, .bus], badge: nil, color: T.warn,
              detail: "9 min caminando · 19 min Metrobús"),
    ]}

    private var activeRoutes: [MapRoute] {
        routes.map { r in
            var copy = r
            copy.isActive = (r.id == selected)
            return copy
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Top bar
                    ScreenHeader(supertitle: "Destino", title: dest, night: night,
                                 onBack: { router.go(.home) })
                        .padding(.horizontal, 16)
                        .padding(.top, 58)
                        .padding(.bottom, 12)

                    // Map
                    mapSection

                    // Summary
                    HStack {
                        Text("3 rutas encontradas")
                            .font(.serif(26))
                            .foregroundStyle(T.pri(night))
                        Spacer()
                        Text("Ahora · 6:47 PM")
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // Route cards
                    VStack(spacing: 12) {
                        ForEach(options) { option in
                            routeCard(option)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky CTA
            VStack(spacing: 0) {
                LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                               startPoint: .top, endPoint: .bottom).frame(height: 36)
                CaminosButton(label: "Ver detalle de ruta", icon: "chevron.right") {
                    router.go(.detail(routeId: selected))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Map section
    private var mapSection: some View {
        ZStack(alignment: .topTrailing) {
            CDMXMap(
                designHeight: 380,
                night: night,
                routes: activeRoutes,
                markers: [
                    .init(point: CGPoint(x: 60, y: 340), kind: .origin),
                    .init(point: CGPoint(x: 330, y: 80), kind: .dest),
                ]
            )

            // Route legend
            VStack(alignment: .trailing, spacing: 6) {
                legendPill("Rápida", color: Color(hex: "2563EB"))
                legendPill("Segura", color: T.safe)
            }
            .padding(.top, 40)
            .padding(.trailing, 12)
        }
    }

    private func legendPill(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(T.pri(night))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(T.surface(night), in: Capsule())
        .caminosCard()
    }

    // MARK: Route card
    @ViewBuilder
    private func routeCard(_ option: RouteOption) -> some View {
        let isSel = selected == option.id
        Button { selected = option.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Badge
                if let badge = option.badge {
                    Text(badge.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(option.color, in: Capsule())
                        .padding(.bottom, 12)
                }

                HStack(alignment: .top, spacing: 16) {
                    // Time column
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.timeMinutes)")
                            .font(.serif(34))
                            .foregroundStyle(T.pri(night))
                        Text("minutos")
                            .font(.mono(11)).tracking(0.5)
                            .foregroundStyle(T.sec(night))
                    }
                    .frame(minWidth: 64, alignment: .leading)

                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(option.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(T.pri(night))
                            SafetyBadge(level: option.safety, vocab: router.vocab, size: .sm)
                        }
                        Text(option.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            ForEach(Array(option.transit.enumerated()), id: \.offset) { i, mode in
                                TransitChip(mode: mode, night: night)
                                if i < option.transit.count - 1 {
                                    LegArrow(night: night)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.surface(night), in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSel ? option.color : Color.clear, lineWidth: 2)
            )
            .caminosCard(hi: isSel)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let r = AppRouter()
    return ScreenResults(dest: "Cafebrería El Péndulo").environment(r)
}
