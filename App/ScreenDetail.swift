import SwiftUI

struct ScreenDetail: View {
    @Environment(AppRouter.self) var router
    var routeId: String = "safe"

    private var night: Bool { router.night }

    private let segments: [RouteSegment] = [
        .init(sfSymbol: "figure.walk",
              mode: "Caminar", duration: "5 min", distance: "380 m",
              from: "Roma Sur", to: "Metrobús Álvaro Obregón",
              safety: .high,
              notes: [
                .init(sfSymbol: "lightbulb.fill", text: "Avenida bien iluminada",        tone: .positive),
                .init(sfSymbol: "person.2.fill",  text: "Alta afluencia de personas",    tone: .positive),
              ]),
        .init(sfSymbol: "tram.fill",
              mode: "Metrobús · Línea 1", duration: "14 min", distance: "6 paradas",
              from: "Álvaro Obregón", to: "Sonora",
              safety: .high,
              notes: [
                .init(sfSymbol: "shield.fill", text: "Vagón con vigilancia", tone: .positive),
              ]),
        .init(sfSymbol: "figure.walk",
              mode: "Caminar", duration: "5 min", distance: "310 m",
              from: "Sonora", to: "Cafebrería El Péndulo",
              safety: .medium,
              notes: [
                .init(sfSymbol: "lightbulb", text: "Iluminación moderada en Álvaro Obregón",         tone: .caution),
                .init(sfSymbol: "exclamationmark.triangle.fill", text: "Zona con reportes recientes después de 22:00", tone: .caution),
              ]),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    ScreenHeader(
                        supertitle: "Ruta segura",
                        title: "Roma Sur → El Péndulo",
                        night: night,
                        onBack: { router.go(.results(dest: "Cafebrería El Péndulo")) },
                        trailing: AnyView(
                            Button {  } label: {
                                Image(systemName: "heart")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(T.pri(night))
                                    .frame(width: 38, height: 38)
                                    .background(T.surface(night), in: Circle())
                                    .caminosCard()
                            }
                            .buttonStyle(.plain)
                        )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 58)
                    .padding(.bottom, 16)

                    // Summary stats
                    summarySection

                    // Timeline
                    timelineSection

                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky CTA
            VStack(spacing: 0) {
                LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                               startPoint: .top, endPoint: .bottom).frame(height: 36)
                CaminosButton(label: "Iniciar navegación segura", icon: "shield.fill") {
                    router.go(.nav)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Summary
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 24) {
                // Large time
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("24")
                        .font(.serif(54))
                        .foregroundStyle(T.pri(night))
                    Text("min")
                        .font(.system(size: 20))
                        .foregroundStyle(T.sec(night))
                        .padding(.bottom, 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SafetyBadge(level: .high, vocab: router.vocab)
                        Text("overall")
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                    }
                    Text("Llegas aprox. **7:11 PM**")
                        .font(.system(size: 13))
                        .foregroundStyle(T.sec(night))
                }
                .padding(.bottom, 4)
            }

            // Segmented safety bar
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 999).fill(T.safe).frame(width: geo.size.width * 5/24)
                    RoundedRectangle(cornerRadius: 999).fill(T.safe).frame(width: geo.size.width * 14/24)
                    RoundedRectangle(cornerRadius: 999).fill(T.warn).frame(width: geo.size.width * 5/24)
                }
                .frame(height: 6)
            }
            .frame(height: 6)

            HStack {
                Text("INICIO").font(.mono(10)).tracking(0.3).foregroundStyle(T.sec(night))
                Spacer()
                Text("14 MIN").font(.mono(10)).tracking(0.3).foregroundStyle(T.sec(night))
                Spacer()
                Text("LLEGADA").font(.mono(10)).tracking(0.3).foregroundStyle(T.sec(night))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: Timeline
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Desglose por tramo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                segmentRow(seg, isLast: i == segments.count - 1)
            }
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: RouteSegment, isLast: Bool) -> some View {
        let safeColor: Color = seg.safety == .high ? T.safe : seg.safety == .medium ? T.warn : T.risk

        HStack(alignment: .top, spacing: 14) {
            // Timeline gutter
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Mode icon
                    RoundedRectangle(cornerRadius: 14)
                        .fill(safeColor)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: seg.sfSymbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        )
                        .zIndex(2)

                    if !isLast {
                        // Dashed connector
                        Rectangle()
                            .fill(T.line(night))
                            .frame(width: 2)
                            .frame(minHeight: 20)
                    }
                }
                .frame(width: 44)
            }
            .frame(width: 44)

            // Segment card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(seg.mode)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                    Spacer()
                    Text("\(seg.duration) · \(seg.distance)")
                        .font(.mono(12)).tracking(0.3)
                        .foregroundStyle(T.sec(night))
                }

                Text("\(seg.from) → \(seg.to)")
                    .font(.system(size: 13))
                    .foregroundStyle(T.sec(night))

                // Notes
                Divider().background(T.line(night))

                VStack(spacing: 8) {
                    ForEach(Array(seg.notes.enumerated()), id: \.offset) { _, note in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(night ? note.color.opacity(0.13) : note.tint)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: note.sfSymbol)
                                        .font(.system(size: 13))
                                        .foregroundStyle(note.color)
                                )
                            Text(note.text)
                                .font(.system(size: 13))
                                .foregroundStyle(T.pri(night))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(T.surface(night), in: RoundedRectangle(cornerRadius: 20))
            .caminosCard()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, isLast ? 0 : 22)
    }
}

#Preview {
    let r = AppRouter()
    return ScreenDetail().environment(r)
}
