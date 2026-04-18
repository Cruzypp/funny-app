import SwiftUI
import FirebaseAuth
import MapKit
import Foundation

struct ScreenNav: View {
    @Environment(AppRouter.self) var router

    @State private var progress: Double = 0.0
    @State private var sharing = true
    @State private var alertVisible = true
    @State private var sosProgress: Double = 0
    @State private var sosPressing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var showSOSOptions = false
    @State private var currentStepIndex = 0
    @State private var routeStepCount = 0
    @State private var progressTimer: Timer?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.defaultCityCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
    )

    private var night: Bool { router.night }

    // Resolved from real route or fallback
    private var routeCoords: [CLLocationCoordinate2D] {
        if let route = router.selectedRoute {
            let sanitized = sanitizeCoordinates(route.polyline.coordinates)
            if sanitized.count >= 2 {
                return sanitized
            }
        }
        return cdmxFallbackRoute
    }

    private var destCoord: CLLocationCoordinate2D {
        router.destCoordinate ?? CLLocationCoordinate2D(latitude: 19.3494, longitude: -99.1617)
    }

    // Fallback: Bellas Artes -> Coyoacan approximation
    private let cdmxFallbackRoute: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 19.4352, longitude: -99.1412),
        CLLocationCoordinate2D(latitude: 19.4308, longitude: -99.1538),
        CLLocationCoordinate2D(latitude: 19.4145, longitude: -99.1671),
        CLLocationCoordinate2D(latitude: 19.3840, longitude: -99.1694),
        CLLocationCoordinate2D(latitude: 19.3494, longitude: -99.1617),
    ]

    private var totalDistanceKm: String {
        guard let route = router.selectedRoute else { return "–" }
        return String(format: "%.1f km", route.distance / 1000)
    }

    private var remainingMinutes: Int {
        guard let route = router.selectedRoute else { return 16 }
        let total = route.expectedTravelTime
        return max(1, Int(total * (1.0 - progress) / 60))
    }

    private var currentInstruction: String {
        guard let route = router.selectedRoute, !route.steps.isEmpty else {
            return "Continúa por la ruta indicada"
        }
        let step = route.steps[min(currentStepIndex, route.steps.count - 1)]
        return step.instructions.isEmpty ? "Continúa recto" : step.instructions
    }

    private var navigationModeLabel: String {
        let modes = router.activeRouteContext?.transportModes ?? [.walk]
        if modes.contains(.metro) { return "Metro + caminata" }
        if modes.contains(.bus) { return "Bus + caminata" }
        return "Caminando"
    }

    var body: some View {
        ZStack {
                Map(position: $cameraPosition) {
                    // Glow + solid polyline
                    if routeCoords.count >= 2 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(T.safe.opacity(0.30), lineWidth: 10)
                        MapPolyline(coordinates: routeCoords)
                            .stroke(T.safe, lineWidth: 4)
                    }

                    // Destination marker
                    Annotation("Destino", coordinate: destCoord, anchor: .bottom) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(T.accent, in: Circle())
                        .shadow(radius: 6)
                }

                    if router.location.userLocation != nil {
                        UserAnnotation()
                    }
                }
            .mapStyle(night
                ? .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
                : .standard(elevation: .realistic)
            )
            .mapControls {
                MapCompass()
                MapScaleView()
            }
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
        .onAppear {
            routeStepCount = router.selectedRoute?.steps.count ?? 0
            startProgress()
            router.location.startTracking()
            Task {
                if let context = router.activeRouteContext {
                    let persisted = await FirebaseService.shared.persistRouteContext(context)
                    router.activeRouteContext = persisted
                }
            }
            // Center map on route start
            if let first = routeCoords.first {
                cameraPosition = .region(MKCoordinateRegion(
                    center: first,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ))
            }
        }
        .onDisappear {
            progressTimer?.invalidate()
            progressTimer = nil
            router.location.stopTracking()
        }
    }

    // MARK: Top glass card
    private var topCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { router.go(.results(dest: router.destName.isEmpty ? "Destino" : router.destName)) } label: {
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
                        Text("NAVEGANDO · \(navigationModeLabel)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(T.sec(night))
                            .tracking(0.3)
                    }
                    Text(currentInstruction)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(T.pri(night))
                        .lineLimit(2)
                }
            }

            // Safety alert mid-route
            if alertVisible && progress > 0.35 && progress < 0.70 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(night ? Color.white : T.warn)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Zona con reportes recientes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(night ? Color.white : T.warn)
                        Text("Baja iluminación · mantente alerta")
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
            Capsule()
                .fill(T.line(night))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 14)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(remainingMinutes)")
                            .font(.serif(40))
                            .foregroundStyle(T.pri(night))
                        Text("min restantes")
                            .font(.system(size: 15))
                            .foregroundStyle(T.sec(night))
                            .padding(.bottom, 3)
                    }
                    Text("LLEGADA · \(arrivalTime()) · \(totalDistanceKm)")
                        .font(.mono(11)).tracking(0.3)
                        .foregroundStyle(T.sec(night))
                }
                Spacer()
                SafetyBadge(level: .medium, vocab: router.vocab)
            }
            .padding(.horizontal, 20)

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

            HStack(spacing: 10) {
                if let loc = router.location.userLocation {
                    ShareLink(item: "Mi ubicación en Caminos: https://maps.apple.com/?ll=\(loc.coordinate.latitude),\(loc.coordinate.longitude)") {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .medium))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Compartir")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Vía enlace")
                                    .font(.system(size: 10))
                                    .opacity(0.75)
                            }
                        }
                        .foregroundStyle(T.pri(night))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 56)
                        .padding(.horizontal, 14)
                        .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 18))
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Compartir")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Sin señal GPS")
                                .font(.system(size: 10))
                                .opacity(0.75)
                        }
                    }
                    .foregroundStyle(T.sec(night))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 56)
                    .padding(.horizontal, 14)
                    .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 18))
                }

                sosButton
                    .frame(width: 56, height: 56)
                    .onChange(of: sosProgress) { _, newValue in
                        if newValue >= 1.0 { triggerEmergency() }
                    }
            }
            .padding(.horizontal, 20)
            .sheet(isPresented: $showSOSOptions) {
                EmergencySheet()
                    .presentationDetents([.medium, .large])
            }

            Text("Mantén presionado SOS por 3s para emergencia")
                .font(.system(size: 11))
                .foregroundStyle(T.sec(night))
                .padding(.top, 10)

            Button {
                Task {
                    let uid: String
                    if let currentUid = Auth.auth().currentUser?.uid {
                        uid = currentUid
                    } else {
                        uid = await FirebaseService.shared.currentUserId()
                    }
                    
                    try? await FirebaseService.shared.updateLocation(
                        userId: uid,
                        lat: router.location.userLocation?.coordinate.latitude ?? destCoord.latitude,
                        lng: router.location.userLocation?.coordinate.longitude ?? destCoord.longitude,
                        estado: .llego
                    )
                    router.go(.survey)
                }
            } label: {
                Text("Llegaste al destino →")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 999).stroke(T.line(night), lineWidth: 1))
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

    // MARK: Helpers
    private func startProgress() {
        pulseScale = 1.1
        progressTimer?.invalidate()
        // Advance progress and update step index based on route steps
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
            if progress >= 1.0 {
                timer.invalidate()
                progressTimer = nil
                return
            }
            progress = min(1.0, progress + 0.001)
            // Update current step
            if routeStepCount > 0 {
                let stepIdx = Int(progress * Double(routeStepCount))
                currentStepIndex = min(stepIdx, routeStepCount - 1)
            }
        }
    }

    private func sanitizeCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        coordinates.filter { coordinate in
            CLLocationCoordinate2DIsValid(coordinate)
                && (-90.0...90.0).contains(coordinate.latitude)
                && (-180.0...180.0).contains(coordinate.longitude)
        }
    }

    private func triggerEmergency() {
        showSOSOptions = true
        sosProgress = 0
        sosPressing = false
    }

    private func arrivalTime() -> String {
        let mins = remainingMinutes
        let arrival = Date().addingTimeInterval(Double(mins) * 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: arrival)
    }
}

#Preview {
    let r = AppRouter()
    return ScreenNav().environment(r)
}
