import MapKit
import SwiftUI

struct ScreenSurvey: View {
    @Environment(AppRouter.self) var router

    @State private var safetyScore = 4
    @State private var lightingScore = 3
    @State private var selectedTags: Set<String> = ["people"]
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var night: Bool { router.night }

    private let allQuickTags: [(id: String, label: String)] = [
        ("people", "Había gente"),
        ("alone", "Zona sola"),
        ("well-lit", "Bien iluminada"),
        ("dark", "Poca luz"),
        ("police", "Vigilancia"),
        ("construction", "Obras"),
        ("smooth", "Banquetas buenas"),
        ("harassment", "Acoso"),
    ]

    private var shouldAskLighting: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 8 || hour >= 18
    }

    private var availableQuickTags: [(id: String, label: String)] {
        if shouldAskLighting {
            return allQuickTags
        }

        return allQuickTags.filter { $0.id != "well-lit" && $0.id != "dark" }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 12) {
                            Text("01 · TOMA 15s")
                                .font(.mono(11)).tracking(1)
                                .foregroundStyle(T.sec(night))
                                .textCase(.uppercase)
                            Rectangle()
                                .fill(T.line(night))
                                .frame(height: 2)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("¿Cómo te sentiste")
                                .font(.serif(36))
                                .foregroundStyle(T.pri(night))
                            Text("en este trayecto?")
                                .font(.serif(36, italic: true))
                                .foregroundStyle(T.sec(night))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 58)
                    .padding(.bottom, 24)

                    sliderSection(
                        title: "Seguridad general",
                        value: $safetyScore,
                        lowLabel: "Muy insegura",
                        highLabel: "Muy segura"
                    )
                    .padding(.horizontal, 20)

                    if shouldAskLighting {
                        sliderSection(title: "Iluminación", value: $lightingScore)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    tagsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    if let submitError {
                        Text(submitError)
                            .font(.system(size: 13))
                            .foregroundStyle(T.risk)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    Color.clear.frame(height: 140)
                }
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
                VStack(spacing: 4) {
                    CaminosButton(
                        label: isSubmitting ? "Enviando..." : "Enviar reporte",
                        icon: isSubmitting ? nil : "heart.fill",
                        variant: .accent
                    ) {
                        Task { await submitSurvey() }
                    }
                    .disabled(isSubmitting)

                    Button {
                        router.lastImpactSummary = nil
                        router.go(.impact)
                    } label: {
                        Text("Omitir")
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            if !shouldAskLighting {
                selectedTags.remove("well-lit")
                selectedTags.remove("dark")
            }
        }
    }

    @ViewBuilder
    private func sliderSection(
        title: String,
        value: Binding<Int>,
        lowLabel: String? = nil,
        highLabel: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.pri(night))
                Spacer()
                Text("\(value.wrappedValue) / 5")
                    .font(.mono(11)).tracking(0.5)
                    .foregroundStyle(T.sec(night))
            }

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { number in
                    let active = number <= value.wrappedValue
                    let color: Color = number <= 2 ? T.risk : number == 3 ? T.warn : T.safe
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            value.wrappedValue = number
                        }
                    } label: {
                        Text("\(number)")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(active ? .white : T.sec(night))
                            .background(
                                active ? color : (night ? Color.white.opacity(0.06) : Color.black.opacity(0.05)),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .scaleEffect(number == value.wrappedValue ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let lowLabel, let highLabel {
                HStack {
                    Text(lowLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(T.sec(night))
                    Spacer()
                    Text(highLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(T.sec(night))
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿Qué notaste?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(T.pri(night))

            FlowLayout(spacing: 8) {
                ForEach(availableQuickTags, id: \.id) { tag in
                    let isSelected = selectedTags.contains(tag.id)
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            if isSelected {
                                selectedTags.remove(tag.id)
                            } else {
                                selectedTags.insert(tag.id)
                            }
                        }
                    } label: {
                        Text((isSelected ? "✓ " : "") + tag.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? T.bg(night) : T.pri(night))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(isSelected ? T.pri(night) : Color.clear, in: Capsule())
                            .overlay(
                                Capsule().stroke(
                                    isSelected ? Color.clear : (night ? Color.white.opacity(0.15) : T.textSecondary.opacity(0.25)),
                                    lineWidth: 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func submitSurvey() async {
        guard !isSubmitting else { return }

        isSubmitting = true
        submitError = nil

        let context = currentReviewContext()

        do {
            let summary = try await FirebaseService.shared.submitRouteReview(
                context: context,
                safetyScore: safetyScore,
                lightingScore: shouldAskLighting ? lightingScore : nil,
                tags: selectedTags
            )
            router.activeRouteContext = context
            router.lastImpactSummary = summary
            router.go(.impact)
        } catch {
            router.activeRouteContext = context
            router.lastImpactSummary = fallbackImpactSummary(for: context)
            router.go(.impact)
        }

        isSubmitting = false
    }

    private func currentReviewContext() -> RouteReviewContext {
        if let context = router.activeRouteContext {
            return context
        }

        let path = router.selectedRoute?.polyline.coordinates ?? []
        let destinationCoordinate = router.destCoordinate ?? path.last
        return RouteReviewContext(
            routeId: nil,
            routeKey: makeRouteKey(origin: router.originName, destination: router.destName.isEmpty ? "Destino" : router.destName),
            originName: router.originName,
            destinationName: router.destName.isEmpty ? "Destino" : router.destName,
            routeLabel: "Ruta completada",
            startedAt: Date(),
            expectedMinutes: max(1, Int((router.selectedRoute?.expectedTravelTime ?? 0) / 60)),
            transportModes: router.activeRouteContext?.transportModes ?? [.walk],
            destinationCoordinate: destinationCoordinate,
            path: path
        )
    }

    private func fallbackImpactSummary(for context: RouteReviewContext) -> RouteImpactSummary {
        RouteImpactSummary(
            routeTitle: context.destinationName,
            routeLabel: context.routeLabel,
            previousAverage: safetyScore,
            currentAverage: safetyScore,
            totalReviews: 1,
            myReviewsThisMonth: 1,
            reportedTags: availableQuickTags
                .filter { selectedTags.contains($0.id) }
                .map(\.label),
            communityTags: [],
            submittedAt: Date(),
            submittedSafetyScore: safetyScore,
            submittedLightingScore: shouldAskLighting ? lightingScore : nil,
            transportModes: context.transportModes,
            savedRemotely: false
        )
    }
}

// MARK: - Simple flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let rowHeights = rows.map { row -> CGFloat in
            row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        }
        let height = rowHeights.reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in computeRows(proposal: .init(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let width = subview.sizeThatFits(.unspecified).width
            if x + width > maxWidth && !rows.last!.isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(subview)
            x += width + spacing
        }

        return rows
    }
}

#Preview {
    let r = AppRouter()
    return ScreenSurvey().environment(r)
}
