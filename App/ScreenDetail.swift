import SwiftUI
import MapKit

struct ScreenDetail: View {
    @Environment(AppRouter.self) var router
    var routeId: String = "safe"

    private var night: Bool { router.night }

    private var segments: [RouteSegment] {
        // If there's a real route, derive segments from its steps
        if let route = router.selectedRoute, route.steps.count >= 2 {
            return routeStepsToSegments(route)
        }
        return cdmxDemoSegments
    }

    private func routeStepsToSegments(_ route: MKRoute) -> [RouteSegment] {
        let usableSteps = route.steps.filter { !$0.instructions.isEmpty }
        guard !usableSteps.isEmpty else { return cdmxDemoSegments }
        return usableSteps.prefix(4).enumerated().map { i, step in
            let mode = stepMode(for: step.instructions)
            let proportionalDuration = route.distance > 0
                ? Int((route.expectedTravelTime * (step.distance / route.distance)) / 60)
                : 0
            let mins = max(1, proportionalDuration)
            let distStr = step.distance < 1000
                ? "\(Int(step.distance)) m"
                : String(format: "%.1f km", step.distance / 1000)
            let isLast = i == usableSteps.prefix(4).count - 1
            return RouteSegment(
                sfSymbol: mode.sfSymbol,
                mode: mode.label,
                duration: "\(mins) min",
                distance: distStr,
                from: i == 0 ? (router.originName) : "Tramo \(i + 1)",
                to: isLast ? (router.destName.isEmpty ? "Destino" : router.destName) : "Continuar",
                safety: mode.safety,
                notes: stepNotes(for: i, mode: mode.kind)
            )
        }
    }

    private func stepNotes(for index: Int, mode: TransitMode) -> [SegmentNote] {
        let walkNotes: [[SegmentNote]] = [
            [
                .init(sfSymbol: "lightbulb.fill", text: "Zona bien iluminada",         tone: .positive),
                .init(sfSymbol: "person.2.fill",  text: "Alta afluencia de personas",   tone: .positive),
            ],
            [
                .init(sfSymbol: "shield.fill",    text: "Área comercial con vigilancia", tone: .positive),
            ],
            [
                .init(sfSymbol: "lightbulb",      text: "Iluminación moderada",          tone: .caution),
            ],
            [
                .init(sfSymbol: "exclamationmark.triangle.fill",
                                                  text: "Reportes nocturnos recientes",  tone: .caution),
            ],
        ]

        let transitNotes: [TransitMode: [SegmentNote]] = [
            .metro: [
                .init(sfSymbol: "tram.fill", text: "Tramo principal en transporte público", tone: .positive),
                .init(sfSymbol: "person.2.fill", text: "Mayor flujo de personas", tone: .positive),
            ],
            .bus: [
                .init(sfSymbol: "bus.fill", text: "Ruta con transbordo en bus", tone: .positive),
                .init(sfSymbol: "clock.fill", text: "Considera tiempos de espera", tone: .caution),
            ],
            .walk: walkNotes[min(index, walkNotes.count - 1)]
        ]

        return transitNotes[mode] ?? walkNotes[min(index, walkNotes.count - 1)]
    }

    private func stepMode(for instructions: String) -> (kind: TransitMode, label: String, sfSymbol: String, safety: SafetyLevel) {
        let normalized = instructions.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalized.contains("metro") || normalized.contains("subway") || normalized.contains("tram") {
            return (.metro, "Metro", "tram.fill", .high)
        }
        if normalized.contains("bus") || normalized.contains("autobus") || normalized.contains("camion") {
            return (.bus, "Bus", "bus.fill", .medium)
        }
        return (.walk, "Caminar", "figure.walk", .high)
    }

    private let cdmxDemoSegments: [RouteSegment] = [
        .init(sfSymbol: "figure.walk",
              mode: "Caminar", duration: "6 min", distance: "450 m",
              from: "Bellas Artes", to: "Metro Juárez",
              safety: .high,
              notes: [
                .init(sfSymbol: "lightbulb.fill", text: "Corredor bien iluminado",        tone: .positive),
                .init(sfSymbol: "person.2.fill",  text: "Alta afluencia peatonal",        tone: .positive),
              ]),
        .init(sfSymbol: "figure.walk",
              mode: "Caminar", duration: "12 min", distance: "900 m",
              from: "Metro Juárez", to: "Insurgentes",
              safety: .high,
              notes: [
                .init(sfSymbol: "shield.fill",    text: "Zona con cámaras y comercio",    tone: .positive),
                .init(sfSymbol: "tram.fill",      text: "Conexión directa a transporte",  tone: .positive),
              ]),
        .init(sfSymbol: "figure.walk",
              mode: "Caminar", duration: "4 min", distance: "280 m",
              from: "Insurgentes", to: "Destino",
              safety: .medium,
              notes: [
                .init(sfSymbol: "lightbulb",      text: "Iluminación moderada de noche",   tone: .caution),
                .init(sfSymbol: "exclamationmark.triangle.fill",
                                                  text: "Reportes recientes después de 22:00", tone: .caution),
              ]),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    ScreenHeader(
                        supertitle: "Ruta segura",
                        title: "\(router.originName.replacingOccurrences(of: "Mi ubicación actual", with: "Origen")) → \(router.destName.isEmpty ? "Destino" : router.destName)",
                        night: night,
                        onBack: { router.go(.results(dest: router.destName.isEmpty ? "Destino" : router.destName)) },
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
                    Text("\(totalMinutes)")
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
                    Text("Llegas aprox. **\(arrivalTime())**")
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

    // MARK: Helpers
    private var totalMinutes: Int {
        if let route = router.selectedRoute {
            return max(1, Int(route.expectedTravelTime / 60))
        }
        return cdmxDemoSegments.compactMap { Int($0.duration.components(separatedBy: " ").first ?? "0") }.reduce(0, +)
    }

    private func arrivalTime() -> String {
        let arrival = Date().addingTimeInterval(Double(totalMinutes) * 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: arrival)
    }
}

#Preview {
    let r = AppRouter()
    return ScreenDetail().environment(r)
}
