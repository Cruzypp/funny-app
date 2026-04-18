import SwiftUI

struct ScreenHome: View {
    @Environment(AppRouter.self) var router
    @State private var destQuery = ""
    @State private var originQuery = ""
    @State private var editingOrigin = false
    @State private var showDestResults = false
    @State private var showOriginResults = false
    @State private var showContactPicker = false
    @FocusState private var focusedField: SearchField?

    private enum SearchField: Hashable {
        case origin
        case destination
    }

    private var night: Bool { router.night }
    private var location: LocationManager { router.location }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    searchCard

                    if showOriginResults && !location.searchResults.isEmpty {
                        searchResultsList(forOrigin: true)
                    }

                    if showDestResults && !location.searchResults.isEmpty {
                        searchResultsList(forOrigin: false)
                    }

                    contactsSection
                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [T.bg(night).opacity(0), T.bg(night)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)

                CaminosButton(label: "Buscar ruta segura", icon: "shield.fill") {
                    searchDestination(fallback: "Parque México")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 38)
                .background(T.bg(night))
            }

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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { dismissKeyboard() }
                    .foregroundStyle(T.accent)
            }
        }
        .onTapGesture { dismissKeyboard() }
        .onAppear {
            location.requestPermission()
        }
        .task {
            await router.loadContacts()
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { newContact in
                Task {
                    await router.addContact(newContact)
                }
            }
        }
        .onChange(of: destQuery) { _, newValue in
            guard !editingOrigin else { return }
            showDestResults = !newValue.isEmpty
            showOriginResults = false
            debounceSearch(query: newValue)
        }
        .onChange(of: originQuery) { _, newValue in
            guard editingOrigin else { return }
            showOriginResults = !newValue.isEmpty
            showDestResults = false
            debounceSearch(query: newValue)
        }
        .onChange(of: editingOrigin) { _, isEditing in
            focusedField = isEditing ? .origin : nil
        }
    }

    private func debounceSearch(query: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if editingOrigin ? (originQuery == query) : (destQuery == query) {
                await location.search(query: query)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hola.")
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

    private var searchCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(T.pri(night)).frame(width: 10, height: 10)

                if editingOrigin {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DESDE")
                            .font(.mono(10)).tracking(0.4)
                            .foregroundStyle(T.sec(night))
                        TextField(
                            "",
                            text: $originQuery,
                            prompt: Text("Buscar origen")
                                .foregroundStyle(T.pri(night).opacity(0.42))
                        )
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(T.pri(night))
                        .tint(T.accent)
                        .focused($focusedField, equals: .origin)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { dismissKeyboard() }
                    }

                    Button {
                        router.originCoordinate = nil
                        router.originName = "Mi ubicación actual"
                        editingOrigin = false
                        originQuery = ""
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(T.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        editingOrigin = true
                        showDestResults = false
                        clearSearchResults()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DESDE")
                                .font(.mono(10)).tracking(0.4)
                                .foregroundStyle(T.sec(night))
                            HStack(spacing: 6) {
                                Text(router.originName)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(T.pri(night))
                                if router.originCoordinate == nil && location.isAuthorized {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(T.safe)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(T.sec(night).opacity(0.5))
                }
            }
            .padding(.horizontal, 4)

            Divider()
                .background(T.line(night))
                .padding(.top, 14)

            HStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(T.accent)
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text("A DÓNDE")
                        .font(.mono(10)).tracking(0.4)
                        .foregroundStyle(T.sec(night))
                    TextField(
                        "",
                        text: $destQuery,
                        prompt: Text("Buscar dirección, lugar o colonia")
                            .foregroundStyle(T.pri(night).opacity(0.48))
                    )
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(T.pri(night))
                    .tint(T.accent)
                    .focused($focusedField, equals: .destination)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { searchDestination() }
                    .onTapGesture {
                        if editingOrigin {
                            editingOrigin = false
                            originQuery = ""
                            clearSearchResults()
                        }
                        focusedField = .destination
                    }
                }

                if !destQuery.isEmpty {
                    Button {
                        destQuery = ""
                        router.destCoordinate = nil
                        router.destName = ""
                        clearSearchResults()
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

    private func searchResultsList(forOrigin: Bool) -> some View {
        Group {
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
                            applySelection(result, forOrigin: forOrigin)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: forOrigin ? "circle.fill" : "mappin.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(forOrigin ? T.pri(night) : T.accent)
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

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contactos de confianza")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T.sec(night))
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("\(router.contacts.count) activos")
                    .font(.system(size: 12))
                    .foregroundStyle(T.sec(night))
            }

            HStack(spacing: 10) {
                if router.contacts.isEmpty {
                    Button {
                        showContactPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .stroke(T.line(night), lineWidth: 1.5)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(T.sec(night))
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Agregar contacto")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(T.pri(night))
                                Text("Elige a alguien desde tu agenda.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(T.sec(night))
                            }

                            Spacer()
                        }
                        .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(router.contacts) { c in
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

                    Button {
                        showContactPicker = true
                    } label: {
                        Circle()
                            .stroke(T.line(night), lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(T.sec(night))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private func clearSearchResults() {
        location.clearSearch()
        showOriginResults = false
        showDestResults = false
    }

    private func dismissKeyboard() {
        focusedField = nil
        clearSearchResults()

        if editingOrigin && originQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editingOrigin = false
        }
    }

    private func applySelection(_ result: AddressResult, forOrigin: Bool) {
        if forOrigin {
            router.originName = result.title
            router.originCoordinate = result.coordinate
            router.originMapItem = result.mapItem
            editingOrigin = false
            originQuery = ""
        } else {
            destQuery = result.title
            router.destName = result.title
            router.destCoordinate = result.coordinate
            router.destMapItem = result.mapItem
            router.go(.results(dest: result.title))
        }

        dismissKeyboard()
    }

    private func searchDestination(fallback: String? = nil) {
        let trimmed = destQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDestination = trimmed.isEmpty ? fallback : trimmed

        guard let finalDestination else { return }

        destQuery = finalDestination
        router.destName = finalDestination
        dismissKeyboard()
        router.go(.results(dest: finalDestination))
    }
}

#Preview {
    let r = AppRouter()
    return ScreenHome().environment(r)
}
