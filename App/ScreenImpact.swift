import SwiftUI

struct ScreenImpact: View {
    @Environment(AppRouter.self) var router

    @State private var displayedScore = 0
    @State private var checkScale: CGFloat = 0.3
    @State private var checkOpacity: Double = 0

    private var night: Bool { router.night }
    private var summary: RouteImpactSummary {
        router.lastImpactSummary ?? fallbackSummary
    }

    private var fallbackSummary: RouteImpactSummary {
        RouteImpactSummary(
            routeTitle: router.destName.isEmpty ? "Tu ruta" : router.destName,
            routeLabel: "Reporte pendiente",
            previousAverage: 0,
            currentAverage: 0,
            totalReviews: 0,
            myReviewsThisMonth: 0,
            reportedTags: [],
            communityTags: [],
            submittedAt: Date(),
            submittedSafetyScore: 0,
            submittedLightingScore: nil,
            transportModes: router.activeRouteContext?.transportModes ?? [.walk],
            savedRemotely: false
        )
    }

    private var scoreDelta: Int {
        summary.currentAverage - summary.previousAverage
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                ZStack(alignment: .top) {
                    RadialGradient(
                        colors: [T.safe.opacity(0.13), Color.clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 300
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
                        highlightsCard
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

    private var heroSection: some View {
        VStack(spacing: 28) {
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
                Text(summary.savedRemotely ? "Reporte guardado." : "Reporte guardado localmente.")
                    .font(.serif(34))
                    .foregroundStyle(T.pri(night))
                Text(summary.routeTitle)
                    .font(.serif(30, italic: true))
                    .foregroundStyle(T.sec(night))
                    .multilineTextAlignment(.center)
            }

            Text(heroCopy)
                .font(.system(size: 15))
                .foregroundStyle(T.sec(night))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 100)
    }

    private var heroCopy: String {
        if summary.totalReviews == 0 {
            return "Tu reseña quedó lista para sincronizarse cuando haya conexión."
        }

        if summary.totalReviews == 1 {
            return "Esta es la primera reseña registrada para este trayecto."
        }

        return "Tu reseña se sumó a \(summary.totalReviews) evaluaciones recientes de esta ruta."
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.routeLabel.uppercased())
                .font(.mono(11)).tracking(1)
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Antes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T.sec(night))
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(summary.previousAverage == 0 ? "—" : "\(summary.previousAverage)")
                        .font(.serif(48))
                        .foregroundStyle(T.warn)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(T.sec(night))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ahora")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T.sec(night))
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(displayedScore == 0 ? "—" : "\(displayedScore)")
                        .font(.serif(48))
                        .foregroundStyle(scoreDelta >= 0 ? T.safe : T.risk)
                        .contentTransition(.numericText(countsDown: scoreDelta < 0))
                        .animation(.easeOut(duration: 0.45), value: displayedScore)
                }
            }

            Divider().background(T.line(night))

            HStack(spacing: 8) {
                Text(deltaLabel)
                    .font(.mono(11)).tracking(0.5).fontWeight(.bold)
                    .foregroundStyle(scoreDelta >= 0 ? T.safe : T.risk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(scoreDelta >= 0 ? T.safeTint : T.riskTint, in: Capsule())

                Text(deltaDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(T.sec(night))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 26))
        .caminosCard(hi: true)
    }

    private var deltaLabel: String {
        if scoreDelta == 0 { return "SIN CAMBIO" }
        return scoreDelta > 0 ? "+\(scoreDelta) PTS" : "\(scoreDelta) PTS"
    }

    private var deltaDescription: String {
        if summary.previousAverage == 0 && summary.currentAverage > 0 {
            return "Ya hay una base inicial de percepción para este trayecto."
        }
        if scoreDelta == 0 {
            return "Tu reseña confirma la percepción actual de esta ruta."
        }
        return scoreDelta > 0
            ? "Tu reseña empujó la percepción de esta ruta hacia un entorno más seguro."
            : "Tu reseña bajó la percepción de seguridad y ayuda a alertar a la comunidad."
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: "\(summary.totalReviews)", label: "reportes en\nesta ruta")
            statCard(value: "\(summary.myReviewsThisMonth)", label: "reportes tuyos\neste mes")
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

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(title: "Tu calificación", value: "\(summary.submittedSafetyScore)/5 en seguridad")

            if let lighting = summary.submittedLightingScore {
                row(title: "Iluminación", value: "\(lighting)/5")
            }

            row(title: "Modo", value: transportModesText)
            row(title: "Enviado", value: submittedAtText)

            if !summary.reportedTags.isEmpty {
                chips(title: "Lo que reportaste", values: summary.reportedTags)
            }

            if !summary.communityTags.isEmpty {
                chips(title: "Se repite en la comunidad", values: summary.communityTags)
            }

            if !summary.savedRemotely {
                Text("Se guardó en este dispositivo y se puede volver a sincronizar después.")
                    .font(.system(size: 12))
                    .foregroundStyle(T.warn)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: 22))
        .caminosCard()
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(T.sec(night))
                .frame(width: 94, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(T.pri(night))
            Spacer()
        }
    }

    private func chips(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)
                .tracking(0.8)
            FlowLayout(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(T.pri(night))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.05), in: Capsule())
                }
            }
        }
    }

    private var transportModesText: String {
        let labels = summary.transportModes.map { mode -> String in
            switch mode {
            case .walk: return "Caminar"
            case .metro: return "Metro"
            case .bus: return "Bus"
            }
        }
        return labels.isEmpty ? "Sin dato" : labels.joined(separator: " + ")
    }

    private var submittedAtText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: summary.submittedAt)
    }

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

    private func runAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            checkScale = 1.0
            checkOpacity = 1.0
        }

        displayedScore = summary.previousAverage
        let target = summary.currentAverage

        guard target != summary.previousAverage else {
            displayedScore = target
            return
        }

        let direction = target > summary.previousAverage ? 1 : -1
        let steps = abs(target - summary.previousAverage)
        for index in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + Double(index) * 0.04) {
                displayedScore = summary.previousAverage + (index * direction)
            }
        }
    }
}

#Preview {
    let router = AppRouter()
    router.lastImpactSummary = RouteImpactSummary(
        routeTitle: "Parque México",
        routeLabel: "Ruta más segura",
        previousAverage: 3,
        currentAverage: 4,
        totalReviews: 8,
        myReviewsThisMonth: 2,
        reportedTags: ["Habia gente", "Vigilancia"],
        communityTags: ["Habia gente", "Poca luz"],
        submittedAt: Date(),
        submittedSafetyScore: 4,
        submittedLightingScore: 3,
        transportModes: [.walk, .bus],
        savedRemotely: true
    )
    return ScreenImpact().environment(router)
}
