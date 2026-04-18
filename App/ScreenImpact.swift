import SwiftUI

struct ScreenImpact: View {
    @Environment(AppRouter.self) var router

    @State private var displayedScore: Int = 62
    @State private var checkScale: CGFloat = 0.3
    @State private var checkOpacity: Double = 0

    private let oldScore = 62
    private let newScore = 71
    private var night: Bool { router.night }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                ZStack(alignment: .top) {
                    // Ambient top glow
                    RadialGradient(
                        colors: [T.safe.opacity(0.13), Color.clear],
                        center: .top, startRadius: 0, endRadius: 300
                    )
                    .frame(height: 420)
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        heroSection
                        scoreCard
                            .padding(.horizontal, 16)
                            .padding(.top, 36)
                        statsRow
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                        ctaSection
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        Color.clear.frame(height: 60)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(T.bg(night))
        .onAppear { runAnimations() }
    }

    // MARK: Hero
    private var heroSection: some View {
        VStack(spacing: 28) {
            // Check circle with pop animation
            ZStack {
                Circle()
                    .fill(T.safe.opacity(0.08))
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(T.safe.opacity(0.04))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(T.safe)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.white)
                    )
            }
            .scaleEffect(checkScale)
            .opacity(checkOpacity)

            VStack(spacing: 10) {
                Text("Gracias, Ana.")
                    .font(.serif(36))
                    .foregroundStyle(T.pri(night))
                Text("tu reporte ayuda.")
                    .font(.serif(36, italic: true))
                    .foregroundStyle(T.sec(night))
            }
            .multilineTextAlignment(.center)

            Text("Ayudaste a **1,247 personas** que van a caminar esta ruta.")
                .font(.system(size: 15))
                .foregroundStyle(T.sec(night))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 100)
    }

    // MARK: Score change card
    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AV. SONORA · TRAMO FINAL")
                .font(.mono(11)).tracking(1)
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)

            HStack(spacing: 16) {
                // Before
                VStack(alignment: .leading, spacing: 4) {
                    Text("Antes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T.sec(night))
                        .textCase(.uppercase).tracking(0.3)
                    Text("\(oldScore)")
                        .font(.serif(48))
                        .foregroundStyle(T.warn)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(T.sec(night))

                // After (animated)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ahora")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T.sec(night))
                        .textCase(.uppercase).tracking(0.3)
                    Text("\(displayedScore)")
                        .font(.serif(48))
                        .foregroundStyle(T.safe)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.easeOut(duration: 0.5), value: displayedScore)
                }
            }

            Divider().background(T.line(night))

            HStack(spacing: 8) {
                Text("+9 PTS")
                    .font(.mono(11)).tracking(0.5).fontWeight(.bold)
                    .foregroundStyle(T.safe)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(T.safeTint, in: Capsule())

                Text("Tu voto movió la percepción de este tramo hacia ")
                    .foregroundStyle(T.sec(night))
                + Text("más seguro").foregroundStyle(T.safe).fontWeight(.semibold)
                + Text(".").foregroundStyle(T.sec(night))
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 26))
        .caminosCard(hi: true)
    }

    // MARK: Stats row
    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: "14",    label: "reportes tuyos\neste mes")
            statCard(value: "2,089", label: "reportes en\ntu zona")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.serif(30))
                .foregroundStyle(T.pri(night))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(T.sec(night))
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 22))
        .caminosCard()
    }

    // MARK: CTAs
    private var ctaSection: some View {
        VStack(spacing: 10) {
            CaminosButton(label: "Ver mapa de la comunidad", icon: "line.3.horizontal.decrease") {
                router.go(.heatmap)
            }
            CaminosButton(label: "Volver al inicio", variant: .ghost) {
                router.go(.home)
            }
        }
    }

    // MARK: Animations
    private func runAnimations() {
        // Check pop
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            checkScale = 1.0
            checkOpacity = 1.0
        }

        // Score count-up
        let steps = newScore - oldScore
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + Double(i) * 0.04) {
                displayedScore = oldScore + i
            }
        }
    }
}

#Preview {
    let r = AppRouter()
    return ScreenImpact().environment(r)
}
