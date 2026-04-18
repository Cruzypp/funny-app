import CoreLocation
import MapKit
import SwiftUI

struct ScreenResults: View {
    @Environment(AppRouter.self) var router
    var dest: String

    @State private var selected = 0
    @State private var mkRoutes: [MKRoute] = []
    @State private var isLoadingRoutes = true
    @State private var errorMessage: String? = nil
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.defaultCityCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    private var night: Bool { router.night }

    private let cdmxFallbackOrigin = CLLocationCoordinate2D(latitude: 19.4352, longitude: -99.1412)
    private let cdmxFallbackDest = CLLocationCoordinate2D(latitude: 19.3494, longitude: -99.1617)

    // Build RouteOptions from real MKRoutes
    private var options: [RouteOption] {
        guard !mkRoutes.isEmpty else { return [] }
        let styles: [(id: String, label: String, safety: SafetyLevel, badge: String?, color: Color)] = [
            ("safe",  "Ruta segura",  .high,   "Recomendada", T.safe),
            ("fast",  "Ruta rápida",  .medium, "Más rápida",  Color(hex: "2563EB")),
            ("mixed", "Ruta mixta",    .medium, "Transporte",  T.warn),
        ]
        
        return mkRoutes.prefix(3).enumerated().map { i, route in
            let s = styles[min(i, styles.count - 1)]
            let mins = max(1, Int(route.expectedTravelTime / 60))
            let transportModes = transportModes(for: route)
            
            // Format details
            let transportText = transportModes.map(transportLabel(for:)).joined(separator: " + ").lowercased()
            let distText = route.distance < 1000
                ? "\(Int(route.distance)) m · \(transportText)"
                : String(format: "%.1f km · %@", route.distance / 1000, transportText)
            
            return RouteOption(id: s.id, label: s.label, timeMinutes: mins,
                               safety: s.safety, transit: transportModes,
                               badge: s.badge, color: s.color, detail: distText)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    ScreenHeader(
                        supertitle: "Destino",
                        title: dest,
                        night: night,
                        onBack: {
                            router.selectedRoute = nil
                            router.go(.home)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 58)
                    .padding(.bottom, 12)

                    mapSection

                    HStack {
                        if isLoadingRoutes {
                            ProgressView().tint(T.sec(night))
                            Text("Calculando rutas…")
                                .font(.serif(20))
                                .foregroundStyle(T.sec(night))
                        } else {
                            Text(mkRoutes.isEmpty
                                 ? "Sin rutas disponibles"
                                 : "\(mkRoutes.count) ruta\(mkRoutes.count > 1 ? "s" : "") encontrada\(mkRoutes.count > 1 ? "s" : "")")
                                .font(.serif(26))
                                .foregroundStyle(T.pri(night))
                        }
                        Spacer()
                        Text(formattedNow())
                            .font(.system(size: 13))
                            .foregroundStyle(T.sec(night))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(T.risk)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }

                    if !isLoadingRoutes && !options.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                                routeCard(option, index: i)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)

            if !isLoadingRoutes && !mkRoutes.isEmpty {
                VStack(spacing: 0) {
                    LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                                   startPoint: .top, endPoint: .bottom).frame(height: 36)
                    CaminosButton(label: "Ver detalle de ruta", icon: "chevron.right") {
                        if selected < mkRoutes.count {
                            let route = mkRoutes[selected]
                            router.selectedRoute = route
                            let opt = options[min(selected, options.count - 1)]
                            let context = RouteReviewContext(
                                routeId: nil,
                                routeKey: makeRouteKey(origin: router.originName, destination: dest),
                                originName: router.originName,
                                destinationName: dest,
                                routeLabel: opt.label,
                                startedAt: Date(),
                                expectedMinutes: opt.timeMinutes,
                                transportModes: opt.transit,
                                destinationCoordinate: router.destCoordinate,
                                path: route.polyline.coordinates
                            )
                            router.activeRouteContext = context
                            
                            Task {
                                let persisted = await FirebaseService.shared.persistRouteContext(context)
                                router.activeRouteContext = persisted
                            }
                        }
                        let ids = ["fast", "safe", "mixed"]
                        router.go(.detail(routeId: ids[min(selected, ids.count - 1)]))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 38)
                    .background(T.bg(night))
                }
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
        .task { await loadRoutes() }
    }

    // MARK: Map
    private var mapSection: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition) {
                ForEach(Array(mkRoutes.prefix(3).enumerated()), id: \.offset) { i, route in
                    let colors: [Color] = [T.safe, Color(hex: "2563EB"), T.warn]
                    let isSelected = i == selected
                    MapPolyline(coordinates: route.polyline.coordinates)
                        .stroke(
                            colors[min(i, colors.count - 1)].opacity(isSelected ? 1.0 : 0.3),
                            lineWidth: isSelected ? 5 : 2.5
                        )
                }

                if let originCoord = effectiveOriginCoord() {
                    Annotation("Origen", coordinate: originCoord, anchor: .center) {
                        Circle()
                            .fill(T.pri(night))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let destCoord = router.destCoordinate {
                    Annotation(dest, coordinate: destCoord, anchor: .bottom) {
                        VStack(spacing: 4) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(T.accent, in: Circle())
                                .shadow(radius: 4)
                            Text(dest)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(T.pri(night))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(T.surface(night), in: Capsule())
                        }
                    }
                }

                UserAnnotation()
            }
            .mapStyle(night ? .standard(pointsOfInterest: .excludingAll) : .standard())
            .mapControls { }
            .frame(height: 280)
        }
    }

    // MARK: Route card
    @ViewBuilder
    private func routeCard(_ option: RouteOption, index: Int) -> some View {
        let isSel = selected == index
        Button { selected = index } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let badge = option.badge {
                    Text(badge.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(option.color, in: Capsule())
                        .padding(.bottom, 12)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.timeMinutes)")
                            .font(.serif(34))
                            .foregroundStyle(T.pri(night))
                        Text("minutos")
                            .font(.mono(11)).tracking(0.5)
                            .foregroundStyle(T.sec(night))
                    }
                    .frame(minWidth: 64, alignment: .leading)
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
                            ForEach(Array(option.transit.enumerated()), id: \.offset) { j, mode in
                                TransitChip(mode: mode, night: night)
                                if j < option.transit.count - 1 { LegArrow(night: night) }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.surface(night), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(isSel ? option.color : Color.clear, lineWidth: 2))
            .caminosCard(hi: isSel)
        }
        .buttonStyle(.plain)
    }

    // MARK: Route loading
    private func loadRoutes() async {
        isLoadingRoutes = true
        errorMessage = nil
        defer { isLoadingRoutes = false }

        // Capture MainActor-isolated values before async context
        let userLocationCoord = router.location.userLocation?.coordinate
        let originName = router.originName
        let originCoord = router.originCoordinate
        let destCoord = router.destCoordinate

        // 1. Resolve source and destination as official MKMapItems (POIs)
        async let originItem = resolveMapItem(name: originName, coord: originCoord ?? userLocationCoord)
        async let destinationItem = resolveMapItem(name: dest, coord: destCoord)
        
        let source = await originItem
        let destination = await destinationItem
        
        // Update router coords to POI coords
        router.originCoordinate = source.placemark.coordinate
        router.destCoordinate = destination.placemark.coordinate

        // 2. Request Transit Routes primarily
        let transitRoutes = await requestTransitRoutes(from: source, to: destination)
        
        // 3. Request Walking Routes as fallback or comparison
        let walkingRoutes = await requestRoutes(from: source, to: destination, type: .walking)

        // 4. Combine and prioritize
        var combined: [MKRoute] = []
        
        // Always take all transit routes first
        combined.append(contentsOf: transitRoutes)
        
        // Add a walking route if it's much faster or if no transit exists
        for wr in walkingRoutes {
            let tooSimilar = combined.contains { abs($0.expectedTravelTime - wr.expectedTravelTime) < 300 }
            if !tooSimilar && combined.count < 3 {
                combined.append(wr)
            }
        }

        self.mkRoutes = combined
        
        if combined.isEmpty {
            errorMessage = "No se encontraron rutas. Verifica tu conexión o intenta con otros puntos."
        }

        // Fit camera
        if let first = combined.first, !combined.isEmpty {
            let boundingRect = combined.reduce(first.polyline.boundingMapRect) { $0.union($1.polyline.boundingMapRect) }
            let region = MKCoordinateRegion(boundingRect)
            cameraPosition = .region(region)
        }
    }

    private func resolveMapItem(name: String, coord: CLLocationCoordinate2D?) async -> MKMapItem {
        // If we have a specific name that isn't "Mi ubicación", search for its official POI
        if name != "Mi ubicación actual" && !name.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name + ", Ciudad de México"
            request.region = LocationManager.defaultCityRegion
            if let response = try? await MKLocalSearch(request: request).start(), let first = response.mapItems.first {
                return first
            }
        }
        
        // Fallback to coordinates if name search fails or is current location
        if let coord = coord {
            return MKMapItem(placemark: MKPlacemark(coordinate: coord))
        }
        
        return MKMapItem(placemark: MKPlacemark(coordinate: cdmxFallbackOrigin))
    }

    private func requestTransitRoutes(from source: MKMapItem, to destination: MKMapItem) async -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .transit
        request.requestsAlternateRoutes = true
        request.departureDate = Date() // CRITICAL for CDMX Metro/Bus

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes
        } catch {
            print("Transit Route Error: \(error.localizedDescription)")
            // Retry once without alternates
            request.requestsAlternateRoutes = false
            return (try? await MKDirections(request: request).calculate().routes) ?? []
        }
    }

    private func requestRoutes(from source: MKMapItem, to destination: MKMapItem, type: MKDirectionsTransportType) async -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = type
        request.requestsAlternateRoutes = true
        return (try? await MKDirections(request: request).calculate().routes) ?? []
    }

    private func effectiveOriginCoord() -> CLLocationCoordinate2D? {
        router.originCoordinate ?? router.location.userLocation?.coordinate
    }

    private func formattedNow() -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return "Ahora · " + f.string(from: Date())
    }

    private func transportModes(for route: MKRoute) -> [TransitMode] {
        var modes: [TransitMode] = []
        
        // Analysis of steps is the most reliable way
        for step in route.steps {
            let instructions = step.instructions.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            
            // Check instructions and transport type
            if instructions.contains("metro") || instructions.contains("subway") || instructions.contains("linea") {
                if modes.last != .metro { modes.append(.metro) }
            } else if instructions.contains("bus") || instructions.contains("autobus") || instructions.contains("metrobus") {
                if modes.last != .bus { modes.append(.bus) }
            } else if instructions.contains("camina") || instructions.contains("walk") {
                // Only add walk if it's a significant part or at the beginning
                if modes.isEmpty || (step.distance > 200 && modes.last != .walk) {
                    modes.append(.walk)
                }
            }
        }
        
        if modes.isEmpty { modes.append(.walk) }
        
        // If Apple says it's transit but we didn't catch the icons, default to show it's mixed
        if route.transportType == .transit && !modes.contains(.metro) && !modes.contains(.bus) {
            modes.insert(.metro, at: 0)
        }
        
        return modes
    }

    private func transportLabel(for mode: TransitMode) -> String {
        switch mode {
        case .walk: return "Caminar"
        case .metro: return "Metro"
        case .bus: return "Bus"
        }
    }
}

#Preview {
    let r = AppRouter()
    r.originName = "Bellas Artes"
    r.originCoordinate = CLLocationCoordinate2D(latitude: 19.4352, longitude: -99.1412)
    return ScreenResults(dest: "Museo Soumaya").environment(r)
}
