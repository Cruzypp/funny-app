import SwiftUI

struct ScreenNav: View {
    @Environment(AppRouter.self) var router

    @State private var progress: Double = 0.35
    @State private var sharing = true
    @State private var alertVisible = true
    @State private var sosProgress: Double = 0
    @State private var sosPressing = false
    @State private var pulseScale: CGFloat = 1.0

    private var night: Bool { router.night }

    // Route points in design space (402 × 874)
    private let routePts: [CGPoint] = [
        [60,340],[150,340],[150,260],[220,260],
        [220,180],[290,180],[290,100],[330,100],[330,80]
    ].map { CGPoint(x: $0[0], y: $0[1]) }

    private var userPos: CGPoint {
        let total = Double(routePts.count - 1)
        let flt = progress * total
        let idx = min(Int(flt), routePts.count - 2)
        let t = flt - Double(idx)
        let a = routePts[idx], b = routePts[idx + 1]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    var body: some View {
        ZStack {
            // Full-bleed map
            CDMXMap(
                designHeight: 874,
                night: night,
                routes: [.init(id: "active", color: T.safe, isActive: true, points: routePts)],
                markers: [.init(point: CGPoint(x: 330, y: 80), kind: .dest)],
                userPos: userPos,
                showLabels: true
            )
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                topCard
                    .padding(.horizontal, 12)
                    .padding(.top, 50)

                Spacer()

                bottomSheet
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { startProgress() }
    }

    // MARK: Top glass card
    private var topCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { router.go(.detail(routeId: "safe")) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(T.pri(night))
                        .frame(width: 32, height: 32)
                        .background(night ? Color.white.opacity(0.10) : Color.black.opacity(0.05),
                                    in: Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(T.safe).frame(width: 6, height: 6)
                            .opacity(pulseScale > 1 ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseScale)
                        Text("NAVEGANDO · Caminando")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(T.sec(night))
                            .tracking(0.3)
                    }
                    Text("En 120 m, gira a la izquierda en Sonora")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                }
            }

            // Alert
            if alertVisible && progress > 0.4 && progress < 0.75 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(night ? Color.white : T.warn)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Entrando a zona de riesgo medio")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(night ? Color.white : T.warn)
                        Text("Baja iluminación · reportes recientes")
                            .font(.system(size: 12))
                            .foregroundStyle(night ? Color.white.opacity(0.85) : T.warn.opacity(0.85))
                    }
                    Spacer()
                    Button { withAnimation { alertVisible = false } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(night ? Color.white : T.warn)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(night ? T.risk.opacity(0.95) : T.warnTint)
                        .overlay(
                            night ? nil : RoundedRectangle(cornerRadius: 18)
                                .stroke(T.warn.opacity(0.13), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .caminosCard(hi: true)
    }

    // MARK: Bottom sheet
    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(T.line(night))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 14)

            // ETA + progress
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("16")
                            .font(.serif(40))
                            .foregroundStyle(T.pri(night))
                        Text("min restantes")
                            .font(.system(size: 15))
                            .foregroundStyle(T.sec(night))
                            .padding(.bottom, 3)
                    }
                    Text("LLEGADA · 7:11 PM · 1.2 KM")
                        .font(.mono(11)).tracking(0.3)
                        .foregroundStyle(T.sec(night))
                }
                Spacer()
                SafetyBadge(level: .medium, vocab: router.vocab)
            }
            .padding(.horizontal, 20)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(night ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                    Capsule()
                        .fill(T.safe)
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: 0.3), value: progress)
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Share + SOS
            HStack(spacing: 10) {
                // Share location
                Button {
                    withAnimation { sharing.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sharing ? "Compartiendo" : "Compartir")
                                .font(.system(size: 13, weight: .semibold))
                            Text(sharing ? "Mamá · Sofía · Diego" : "con contactos")
                                .font(.system(size: 10))
                                .opacity(0.75)
                        }
                    }
                    .foregroundStyle(sharing ? T.safe : T.pri(night))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 56)
                    .padding(.horizontal, 14)
                    .background(
                        sharing
                            ? (night ? T.safe.opacity(0.25) : T.safeTint)
                            : (night ? Color.white.opacity(0.06) : Color.black.opacity(0.04)),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }
                .buttonStyle(.plain)

                // SOS (hold to activate)
                sosButton
                    .frame(width: 56, height: 56)
            }
            .padding(.horizontal, 20)

            Text("Mantén presionado SOS por 3s para emergencia")
                .font(.system(size: 11))
                .foregroundStyle(T.sec(night))
                .padding(.top, 10)

            // Dev: skip to survey
            Button { router.go(.survey) } label: {
                Text("Llegaste al destino →")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(T.line(night), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .background(T.surface(night))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 40, y: -10)
    }

    // MARK: SOS button
    private var sosButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(T.risk)

            // Fill progress overlay
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: geo.size.height * sosProgress)
                        .animation(.linear(duration: sosPressing ? 3.0 : 0.2), value: sosProgress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            Text("SOS")
                .font(.system(size: 12, weight: .black))
                .tracking(1)
                .foregroundStyle(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !sosPressing {
                        sosPressing = true
                        withAnimation { sosProgress = 1.0 }
                    }
                }
                .onEnded { _ in
                    sosPressing = false
                    withAnimation(.easeOut(duration: 0.2)) { sosProgress = 0 }
                }
        )
    }

    // MARK: Timer
    private func startProgress() {
        pulseScale = 1.1
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { t in
            if progress >= 1.0 { t.invalidate(); return }
            progress = min(1.0, progress + 0.002)
        }
    }
}

#Preview {
    let r = AppRouter()
    return ScreenNav().environment(r)
}
