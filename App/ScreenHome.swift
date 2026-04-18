import SwiftUI
import CoreLocation

struct ScreenHome: View {
    @Environment(AppRouter.self) var router
    @State private var query = ""
    @State private var showResults = false

    private let contacts: [TrustedContact] = [
        .init(name: "Mamá",  color: Color(hex: "E07856")),
        .init(name: "Sofía", color: Color(hex: "2E7D5B")),
        .init(name: "Diego", color: Color(hex: "3A5998")),
    ]

    private let recents: [RecentDestination] = [
        .init(sfSymbol: "house.fill",      title: "Casa",              subtitle: "Col. Roma Norte",    safety: .high),
        .init(sfSymbol: "briefcase.fill",  title: "Oficina",           subtitle: "Av. Reforma 222",    safety: .high),
        .init(sfSymbol: "clock",           title: "Gimnasio Condesa",  subtitle: "Michoacán 78",       safety: .medium),
        .init(sfSymbol: "clock",           title: "Casa de Ana",       subtitle: "Col. Del Valle",     safety: .medium),
    ]

    private var night: Bool { router.night }
    private var location: LocationManager { router.location }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    searchCard

                    // Search results dropdown
                    if showResults && !location.searchResults.isEmpty {
                        searchResultsList
                    }

                    locateButton
                    contactsSection
                    recentsSection
                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky CTA
            VStack(spacing: 0) {
                LinearGradient(colors: [T.bg(night).opacity(0), T.bg(night)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                    .allowsHitTesting(false)
                CaminosButton(label: "Buscar ruta segura", icon: "shield.fill") {
                    router.go(.results(dest: query.isEmpty ? "Cafebrería El Péndulo" : query))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }

            // Heatmap button — fuera del ScrollView para evitar conflictos de gestos
            VStack {
                HStack {
                    Spacer()
                    Button { router.go(.heatmap) } label: {
                        Image(systemName: "map.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(T.pri(night))
                            .frame(width: 50, height: 50)
                            .background(T.surface(night), in: Circle())
                            .caminosCard(hi: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.top, 80)
                }
                Spacer()
            }
        }
        .background(T.bg(night))
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            location.requestPermission()
        }
        .onChange(of: query) { _, newValue in
            showResults = !newValue.isEmpty
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                // Only search if query hasn't changed since sleep
                if query == newValue {
                    await location.search(query: newValue)
                }
            }
        }
    }

    // MARK: Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hola, Ana.")
                .font(.serif(42))
                .foregroundStyle(T.pri(night))
            Text("¿a dónde vas?")
                .font(.serif(42, italic: true))
                .foregroundStyle(T.sec(night))
        }
        .padding(.horizontal, 20)
        .padding(.top, 80)
        .padding(.bottom, 20)
    }

    // MARK: Search card
    private var searchCard: some View {
        VStack(spacing: 0) {
            // Origin row
            HStack(spacing: 12) {
                Circle().fill(T.pri(night)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DESDE")
                        .font(.mono(10)).tracking(0.4)
                        .foregroundStyle(T.sec(night))
                    Text(location.isAuthorized
                         ? "Mi ubicación actual"
                         : "Mi ubicación · Roma Sur")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(T.pri(night))
                }
            }
            .padding(.horizontal, 4)

            // Connector dots
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(T.sec(night)).frame(width: 2, height: 2)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Divider().background(T.line(night))

            // Destination row
            HStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(T.accent)
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text("A DÓNDE")
                        .font(.mono(10)).tracking(0.4)
                        .foregroundStyle(T.sec(night))
                    TextField("Buscar dirección, lugar o contacto", text: $query)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(T.pri(night))
                        .tint(T.accent)
                        .submitLabel(.search)
                        .onSubmit {
                            if !query.isEmpty {
                                router.go(.results(dest: query))
                            }
                        }
                }

                // Clear button
                if !query.isEmpty {
                    Button {
                        query = ""
                        location.clearSearch()
                        showResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(T.sec(night))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 14)
        }
        .padding(16)
        .background(T.surface(night), in: RoundedRectangle(cornerRadius: T.r4))
        .caminosCard()
        .padding(.horizontal, 16)
    }

    // MARK: Search results list
    private var searchResultsList: some View {
        VStack(spacing: 0) {
            if location.isSearching {
                HStack {
                    ProgressView().tint(T.sec(night))
                    Text("Buscando…")
                        .font(.system(size: 14))
                        .foregroundStyle(T.sec(night))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(T.surface(night), in: RoundedRectangle(cornerRadius: T.r4))
                .padding(.horizontal, 16)
                .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(location.searchResults.enumerated()), id: \.element.id) { i, result in
                        Button {
                            query = result.title
                            showResults = false
                            location.clearSearch()
                            router.go(.results(dest: result.title))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(T.accent)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(T.pri(night))
                                        .lineLimit(1)
                                    Text(result.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(T.sec(night))
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if i < location.searchResults.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(T.surface(night), in: RoundedRectangle(cornerRadius: T.r4))
                .caminosCard()
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
    }

    // MARK: Locate button
    private var locateButton: some View {
        Button {
            if let loc = location.userLocation {
                // Reverse-geocode and set as destination
                let geocoder = CLGeocoder()
                Task {
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
                       let name = placemarks.first?.name ?? placemarks.first?.locality {
                        query = name
                        router.go(.results(dest: name))
                    }
                }
            } else {
                location.requestPermission()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: location.isAuthorized ? "location.fill" : "location")
                    .font(.system(size: 15))
                Text(location.isAuthorized
                     ? "Usar mi ubicación como destino"
                     : "Activar ubicación")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(location.isAuthorized ? T.accent : T.sec(night))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: Trusted contacts
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contactos de confianza")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T.sec(night))
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("3 activos")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
            }

            HStack(spacing: 10) {
                ForEach(contacts, id: \.name) { c in
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(String(c.name.prefix(1)))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            )

                        Circle()
                            .fill(T.safe)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(T.bg(night), lineWidth: 2.5))
                            .offset(x: 2, y: 2)
                    }
                }

                // Add button
                Circle()
                    .stroke(T.line(night), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(T.sec(night))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: Recent destinations
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destinos recientes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(T.sec(night))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 20)

            ForEach(recents) { r in
                Button {
                    router.go(.results(dest: r.title))
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(night ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: r.sfSymbol)
                                    .font(.system(size: 16))
                                    .foregroundStyle(T.pri(night))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(T.pri(night))
                            Text(r.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(T.sec(night))
                        }
                        Spacer()
                        SafetyBadge(level: r.safety, vocab: router.vocab, size: .sm)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 20)
    }
}

#Preview {
    let r = AppRouter()
    return ScreenHome().environment(r)
}
