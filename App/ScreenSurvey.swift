import SwiftUI

struct ScreenSurvey: View {
    @Environment(AppRouter.self) var router

    @State private var safetyScore = 4
    @State private var lightingScore = 3
    @State private var selectedTags: Set<String> = ["people"]
    @State private var comment = ""

    private var night: Bool { router.night }

    private let quickTags: [(id: String, label: String)] = [
        ("people",       "Había gente"),
        ("alone",        "Zona sola"),
        ("well-lit",     "Bien iluminada"),
        ("dark",         "Poca luz"),
        ("police",       "Vigilancia"),
        ("construction", "Obras"),
        ("smooth",       "Banquetas buenas"),
        ("harassment",   "Acoso"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
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

                    // Safety slider
                    sliderSection(
                        title: "Seguridad general",
                        value: $safetyScore,
                        lowLabel: "Muy insegura",
                        highLabel: "Muy segura"
                    )
                    .padding(.horizontal, 20)

                    // Lighting slider
                    sliderSection(
                        title: "Iluminación",
                        value: $lightingScore
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Quick tags
                    tagsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    // Comment
                    commentSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    Color.clear.frame(height: 140)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky CTAs
            VStack(spacing: 0) {
                LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                               startPoint: .top, endPoint: .bottom).frame(height: 30)
                VStack(spacing: 4) {
                    CaminosButton(label: "Enviar reporte", icon: "heart.fill", variant: .accent) {
                        router.go(.impact)
                    }
                    Button { router.go(.impact) } label: {
                        Text("Omitir")
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Slider (1–5 buttons)
    @ViewBuilder
    private func sliderSection(
        title: String, value: Binding<Int>,
        lowLabel: String? = nil, highLabel: String? = nil
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
                ForEach(1...5, id: \.self) { n in
                    let active = n <= value.wrappedValue
                    let col: Color = n <= 2 ? T.risk : n == 3 ? T.warn : T.safe
                    Button { withAnimation(.spring(response: 0.25)) { value.wrappedValue = n } } label: {
                        Text("\(n)")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(active ? .white : T.sec(night))
                            .background(
                                active ? col : (night ? Color.white.opacity(0.06) : Color.black.opacity(0.05)),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .scaleEffect(n == value.wrappedValue ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let low = lowLabel, let high = highLabel {
                HStack {
                    Text(low).font(.system(size: 11)).foregroundStyle(T.sec(night))
                    Spacer()
                    Text(high).font(.system(size: 11)).foregroundStyle(T.sec(night))
                }
            }
        }
    }

    // MARK: Quick tags
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿Qué notaste?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(T.pri(night))

            FlowLayout(spacing: 8) {
                ForEach(quickTags, id: \.id) { tag in
                    let on = selectedTags.contains(tag.id)
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            if on { selectedTags.remove(tag.id) }
                            else { selectedTags.insert(tag.id) }
                        }
                    } label: {
                        Text((on ? "✓ " : "") + tag.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? T.bg(night) : T.pri(night))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(
                                on ? T.pri(night) : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    on ? Color.clear
                                       : (night ? Color.white.opacity(0.15) : T.textSecondary.opacity(0.25)),
                                    lineWidth: 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Comment
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comentario (opcional)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(T.sec(night))

            TextField("Cuéntanos algo específico…", text: $comment, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(T.pri(night))
                .lineLimit(3...6)
                .padding(14)
                .background(T.surface(night), in: RoundedRectangle(cornerRadius: 18))
                .caminosCard()
        }
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
            let rowH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for sv in row {
                let s = sv.sizeThatFits(.unspecified)
                sv.place(at: CGPoint(x: x, y: y), proposal: .init(s))
                x += s.width + spacing
            }
            y += rowH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for sv in subviews {
            let w = sv.sizeThatFits(.unspecified).width
            if x + w > maxW && !rows.last!.isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(sv)
            x += w + spacing
        }
        return rows
    }
}

#Preview {
    let r = AppRouter()
    return ScreenSurvey().environment(r)
}
