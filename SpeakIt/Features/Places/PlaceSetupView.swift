import CoreLocation
import MapKit
import SwiftUI

/// Sets the coordinate that `PlaceReference.home` or `.work` resolves to.
///
/// What this screen edits is the *resolution*, never the intent. Every reminder
/// that says "home" keeps saying "home"; saving here changes what home currently
/// means and `SavedPlaceStore.didChangeNotification` makes the reminders follow.
/// Someone who moves house does not re-record a single thought.
struct PlaceSetupView: View {
    /// Which saved place this screen is setting. Only `.home` and `.work` are
    /// storable references, so anything else is a programming error rather than
    /// a state to render.
    let reference: PlaceReference

    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition
    /// The coordinate under the crosshair. Read from the camera rather than from
    /// a draggable pin, so the whole map is the control and there is no small
    /// target to hit.
    @State private var center: CLLocationCoordinate2D
    @State private var label: String?
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isLocating = false
    @State private var errorMessage: String?
    /// The centre this view just moved the camera to itself.
    ///
    /// `onMapCameraChange` cannot tell a finger drag from a programmatic recentre,
    /// and both arrive after the fact. Without this, picking "Massey Hall" from
    /// search sets the label and then immediately has it cleared by the camera
    /// change that the selection itself caused — the place saves with no name.
    @State private var programmaticCenter: CLLocationCoordinate2D?

    private let provider = CurrentLocationProvider()
    private let geocoder = CLGeocoder()

    /// Toronto, only as the "we have nothing at all" fallback. Any saved place,
    /// and any successful current-location read, replaces it immediately.
    private static let fallbackCenter = CLLocationCoordinate2D(
        latitude: 43.6532,
        longitude: -79.3832
    )

    init(reference: PlaceReference) {
        self.reference = reference
        let saved = SavedPlaceStore.place(for: reference)
        let start = saved.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? Self.fallbackCenter
        _center = State(initialValue: start)
        _label = State(initialValue: saved?.label)
        _camera = State(initialValue: .region(
            MKCoordinateRegion(
                center: start,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        ))
    }

    var body: some View {
        Form {
            Section {
                mapPicker
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Drag the map to place the marker. Speak It reminds you when you arrive within about \(Int(ResolvedPlace.defaultRadius)) metres of it.")
            }

            Section {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        Label("Use my current location", systemImage: "location")
                        Spacer()
                        if isLocating { ProgressView() }
                    }
                }
                .disabled(isLocating)
                .accessibilityHint("Centres the map on where you are now")
            }

            Section("Search for an address") {
                TextField("Address or place name", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }

                ForEach(searchResults, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unnamed place")
                                .foregroundStyle(Color.speakInk)
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if SavedPlaceStore.place(for: reference) != nil {
                Section {
                    Button(role: .destructive) {
                        SavedPlaceStore.set(nil, for: reference)
                        dismiss()
                    } label: {
                        Text("Remove \(reference.displayName)")
                    }
                } footer: {
                    Text("Reminders that mention \(reference.displayName) are kept. They wait until you set it again.")
                }
            }
        }
        .navigationTitle("Set \(reference.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .alert(
            "Location",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var mapPicker: some View {
        ZStack {
            Map(position: $camera)
                .onMapCameraChange(frequency: .onEnd) { context in
                    let newCenter = context.region.center
                    center = newCenter
                    // A recentre this view asked for keeps whatever name came
                    // with it. Only a drag by hand invalidates the label, since
                    // then the coordinate no longer matches the address.
                    if let programmaticCenter,
                       Self.isEffectivelySame(programmaticCenter, newCenter) {
                        self.programmaticCenter = nil
                    } else {
                        programmaticCenter = nil
                        label = nil
                    }
                }
                .accessibilityLabel("Map. Drag to choose \(reference.displayName).")

            // A fixed centre marker rather than a draggable annotation: the map
            // moves under it, so there is no small target to grab and the
            // gesture works the same at every zoom level.
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.speakAccent)
                .shadow(radius: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func save() {
        SavedPlaceStore.set(
            SavedPlace(
                latitude: center.latitude,
                longitude: center.longitude,
                label: label
            ),
            for: reference
        )
        dismiss()
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let coordinate = try await provider.currentCoordinate()
            center = coordinate
            programmaticCenter = coordinate
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
            await reverseGeocode(coordinate)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Speak It couldn't read your location."
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Bias to what is on screen: someone typing "Main Street" while looking
        // at their own neighbourhood means that one.
        request.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = Array(response.mapItems.prefix(8))
        } catch {
            searchResults = []
            errorMessage = "Speak It couldn't search for that place."
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        center = coordinate
        programmaticCenter = coordinate
        label = item.name ?? item.placemark.title
        camera = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        )
        searchResults = []
        searchText = ""
    }

    /// Whether two coordinates are the same place for labelling purposes.
    ///
    /// The camera reports back a centre that has been through a projection and
    /// a snap to the rendered region, so it is near the requested point rather
    /// than exactly it. About 11 metres, which is far tighter than the 150m
    /// region and far looser than the rounding error.
    private static func isEffectivelySame(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.0001
            && abs(lhs.longitude - rhs.longitude) < 0.0001
    }

    /// Names the coordinate so the settings row can say what Home means without
    /// a lookup later. Best-effort: a place with no readable address is still a
    /// perfectly good place.
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        guard let placemark = placemarks?.first else { return }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        label = street.isEmpty ? placemark.locality : street
    }
}

/// Lists the places a person can configure once and refer to by name.
struct SavedPlacesView: View {
    /// Bumped whenever a place is saved, so the rows re-read the store on
    /// return from the picker.
    @State private var revision = 0

    var body: some View {
        Form {
            Section {
                placeRow(.home, symbol: "house")
                placeRow(.work, symbol: "briefcase")
            } footer: {
                Text("Speak It uses these when you say things like “remind me when I get home” or “when I leave work”. Changing one updates every reminder that mentions it — you never have to edit the reminders themselves.")
            }
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(
            NotificationCenter.default.publisher(for: SavedPlaceStore.didChangeNotification)
        ) { _ in
            revision += 1
        }
    }

    private func placeRow(_ reference: PlaceReference, symbol: String) -> some View {
        NavigationLink {
            PlaceSetupView(reference: reference)
        } label: {
            HStack {
                Label(reference.displayName, systemImage: symbol)
                Spacer()
                Text(subtitle(for: reference))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .id(revision)
    }

    private func subtitle(for reference: PlaceReference) -> String {
        guard let place = SavedPlaceStore.place(for: reference) else { return "Not set" }
        return place.label ?? "Set"
    }
}
