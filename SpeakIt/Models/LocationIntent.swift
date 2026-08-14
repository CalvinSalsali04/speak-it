import Foundation

/// What the person wants to happen at a place.
enum LocationEvent: String, Codable, CaseIterable, Sendable {
    /// "when I get home"
    case arrive
    /// "when I leave work"
    case leave

    var verbPhrase: String {
        switch self {
        case .arrive: "arrive at"
        case .leave: "leave"
        }
    }
}

/// The place a person named, kept as what they said rather than as coordinates.
///
/// This is the location half of the same rule the temporal system enforces:
/// **record the meaning, resolve it separately.** "Home" is not a latitude and
/// longitude — it is a reference that resolves to one, and the resolution can
/// change without the request changing. Someone who moves house has not edited
/// their reminder. Collapsing "home" to coordinates at capture time would throw
/// away the one piece of information needed to follow them to the new address.
enum PlaceReference: Codable, Equatable, Sendable {
    /// The saved Home place.
    case home
    /// The saved Work place.
    case work
    /// "here" — wherever the person was standing when they said it.
    ///
    /// The one reference that is a **snapshot rather than a pointer**, and the
    /// distinction is the whole point. `.home` means "wherever home is now", so
    /// moving house follows it. `"here"` means "this spot, the one I was
    /// standing on" — said at McMaster and carried to Toronto it must still mean
    /// McMaster, because the coordinate *is* the meaning. Re-resolving it
    /// against the current position would silently rewrite the request into
    /// "wherever I happen to be", which is not a reminder at all.
    ///
    /// So it is resolved once, at capture, into `LocationIntent.resolvedPlace`
    /// and never resolved again.
    case currentLocation
    /// A place named in words: "Costco", "the gym". Needs searching, and may
    /// legitimately match more than one location.
    case named(String)

    /// What to call this place in a row or a notification.
    var displayName: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .currentLocation: "here"
        case let .named(name): name
        }
    }

    /// True when this reference points at a place the person configures once
    /// and reuses, so a missing one is a setup gap rather than a bad sentence.
    var isSavedPlace: Bool {
        switch self {
        case .home, .work: true
        case .currentLocation, .named: false
        }
    }
}

/// A place resolved to something CoreLocation can monitor.
///
/// Deliberately a separate value from `PlaceReference`. The reference is what
/// the person meant and is stable; this is how it currently resolves and is
/// disposable. Re-resolving after someone changes their Home address replaces
/// this and leaves the intent untouched.
struct ResolvedPlace: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Metres. Region monitoring is not precise, and too small a radius simply
    /// never triggers.
    var radius: Double
    /// What the resolution matched, so the UI can confirm the right Costco.
    var matchedName: String?
    var resolvedAt: Date

    static let defaultRadius: Double = 150

    init(
        latitude: Double,
        longitude: Double,
        radius: Double = ResolvedPlace.defaultRadius,
        matchedName: String? = nil,
        resolvedAt: Date = .now
    ) {
        self.latitude = latitude
        self.longitude = longitude
        // A region smaller than the platform's own accuracy floor will not fire.
        self.radius = max(radius, 100)
        self.matchedName = matchedName
        self.resolvedAt = resolvedAt
    }
}

/// What the person said about a place, before it is resolved into a region.
///
/// The exact counterpart of `TemporalIntent`, and separate from it on purpose.
/// Location is not a kind of time, and folding it into the temporal model as
/// another case would have meant every temporal code path growing a branch that
/// could not mean anything.
///
/// Notably absent: permission. See `LocationAuthorization` for why.
struct LocationIntent: Codable, Equatable, Sendable {
    var event: LocationEvent
    var place: PlaceReference
    /// "every time I get to work" repeats; "next time I get to the gym" does
    /// not. A one-shot reminder stops being monitored once it fires.
    var repeats: Bool
    /// How the place currently resolves, when it has been resolved. Absent is a
    /// normal state, not an error: a named place may not have been searched
    /// yet, and a saved place may not have been configured yet.
    var resolvedPlace: ResolvedPlace?
    /// The wording this was read from. Provenance, not truth — the same
    /// contract `TemporalIntent.sourceText` has.
    var sourceText: String?
    /// True once a person has set the place by hand, after which no reparse of
    /// the original sentence may overwrite it.
    var isUserEdited: Bool

    init(
        event: LocationEvent,
        place: PlaceReference,
        repeats: Bool = false,
        resolvedPlace: ResolvedPlace? = nil,
        sourceText: String? = nil,
        isUserEdited: Bool = false
    ) {
        self.event = event
        self.place = place
        self.repeats = repeats
        self.resolvedPlace = resolvedPlace
        self.sourceText = sourceText
        self.isUserEdited = isUserEdited
    }

    /// Tolerates intents written before a field existed, the same way
    /// `TemporalIntent` does, so adding one never orphans a stored row.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decodeIfPresent(LocationEvent.self, forKey: .event) ?? .arrive
        place = try container.decode(PlaceReference.self, forKey: .place)
        repeats = try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? false
        resolvedPlace = try container.decodeIfPresent(ResolvedPlace.self, forKey: .resolvedPlace)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        isUserEdited = try container.decodeIfPresent(Bool.self, forKey: .isUserEdited) ?? false
    }

    /// A short phrase for a row: "when you arrive at Home".
    ///
    /// A resolved `"here"` prefers the name the snapshot was given, so the row
    /// reads "when you leave McMaster University" rather than "when you leave
    /// here" — which, read back a week later, names nowhere at all. The name is
    /// presentation only: an unnamed snapshot still fires perfectly well, and
    /// falls back to the word the person actually said.
    var displayDescription: String {
        "when you \(event.verbPhrase) \(displayPlaceName)"
    }

    /// What to call this intent's place in a row.
    var displayPlaceName: String {
        if case .currentLocation = place,
           let name = resolvedPlace?.matchedName,
           !name.isEmpty {
            return name
        }
        return place.displayName
    }
}

/// Why a location reminder cannot currently be monitored.
///
/// Deliberately not one "needs review" bucket. These have genuinely different
/// answers — one needs a Settings trip, one needs a Home address, one needs the
/// person to pick which Costco — and showing "What did you mean?" for a
/// perfectly clear sentence is the exact mistake the temporal system already
/// refuses to make for "when I get home".
enum LocationReminderBlocker: String, Codable, CaseIterable, Sendable {
    /// The app has never been granted location access.
    case permissionRequired
    /// Granted, then revoked. The reminder is kept; only monitoring stopped.
    case permissionRevoked
    /// "While Using" only. Region monitoring needs Always to fire in the
    /// background, which is the only time it is useful.
    case alwaysPermissionRequired
    /// Precise Location is off, so a region this size cannot be trusted.
    case preciseLocationRequired
    /// The wording says Home and no Home is configured.
    case missingHome
    /// The wording says Work and no Work is configured.
    case missingWork
    /// A named place matched more than one plausible location.
    case ambiguousPlace
    /// A named place matched nothing.
    case placeNotFound
    /// The device cannot report a location right now.
    case locationUnavailable
    /// The platform cannot monitor regions on this device at all.
    case monitoringUnavailable
    /// iOS caps how many regions one app may monitor, and the cap is reached.
    case monitoringLimitReached

    /// Shown on the review row. Names the actual gap, in the person's terms.
    var listLabel: String {
        switch self {
        case .permissionRequired: "Needs location permission"
        case .permissionRevoked: "Location access was turned off"
        case .alwaysPermissionRequired: "Needs “Always” location access"
        case .preciseLocationRequired: "Needs Precise Location"
        case .missingHome: "Set your Home location"
        case .missingWork: "Set your Work location"
        case .ambiguousPlace: "Which one?"
        case .placeNotFound: "Place not found"
        case .locationUnavailable: "Location unavailable"
        case .monitoringUnavailable: "Place reminders unavailable"
        case .monitoringLimitReached: "Too many place reminders"
        }
    }

    /// Shown in the editor, above whatever the person has to supply.
    var editorPrompt: String {
        switch self {
        case .permissionRequired:
            "Allow location access so Speak It can remind you here"
        case .permissionRevoked:
            "Location access was turned off — turn it back on to use this reminder"
        case .alwaysPermissionRequired:
            "A place reminder has to reach you when Speak It is closed, so iOS needs location access set to “Always”. Speak It checks only whether you crossed this one place — it does not track where you go, and nothing leaves your iPhone."
        case .preciseLocationRequired:
            "Turn on Precise Location so Speak It knows when you arrive"
        case .missingHome:
            "Set your Home location"
        case .missingWork:
            "Set your Work location"
        case .ambiguousPlace:
            "Choose which place you meant"
        case .placeNotFound:
            "Speak It couldn't find that place — pick it on the map"
        case .locationUnavailable:
            "Speak It can't read your location right now"
        case .monitoringUnavailable:
            "This device can't monitor places"
        case .monitoringLimitReached:
            "Turn off another place reminder to make room for this one"
        }
    }

    /// True when the person fixes this in Settings rather than in Speak It.
    var isResolvedInSettings: Bool {
        switch self {
        case .permissionRequired, .permissionRevoked, .alwaysPermissionRequired,
             .preciseLocationRequired:
            true
        case .missingHome, .missingWork, .ambiguousPlace, .placeNotFound,
             .locationUnavailable, .monitoringUnavailable, .monitoringLimitReached:
            false
        }
    }
}

/// Turns a location intent into something monitorable, or says exactly why not.
///
/// The three things the architecture insists on keeping apart meet here, and
/// only here:
///
/// 1. **what place the person meant** — `LocationIntent.place`, stable
/// 2. **how that place currently resolves** — a saved place or a stored
///    `ResolvedPlace`, replaceable
/// 3. **whether the device may monitor it** — `LocationAuthorization`, queried
///    fresh every time and never written down
///
/// Keeping (2) out of (1) is what lets someone move house without editing their
/// reminders: `.home` still means home, and re-resolving is a lookup rather than
/// a rewrite. Keeping (3) out of both is what lets permission come and go
/// without a reminder ever being deleted or silently disabled.
@MainActor
enum LocationReminderResolver {
    struct Resolution: Equatable {
        /// Present when this reminder can be monitored right now.
        var request: LocationMonitorRequest?
        /// Present when it cannot, naming the actual problem.
        var blocker: LocationReminderBlocker?

        var isActionable: Bool { request != nil }
    }

    static func resolve(
        _ intent: LocationIntent,
        itemID: UUID,
        title: String,
        authorization: LocationAuthorization
    ) -> Resolution {
        // Permission first: it blocks every place equally, and telling someone
        // to set a Home address they cannot use yet is the wrong instruction.
        if let blocker = authorization.blocker {
            return Resolution(blocker: blocker)
        }

        guard let place = resolvedPlace(for: intent) else {
            return Resolution(blocker: missingPlaceBlocker(for: intent.place))
        }

        return Resolution(request: LocationMonitorRequest(
            itemID: itemID,
            title: title,
            event: intent.event,
            place: place,
            repeats: intent.repeats
        ))
    }

    /// How this intent's place resolves right now.
    ///
    /// A saved place is read live rather than from the intent's cached
    /// `resolvedPlace`, which is the whole point of storing the reference: when
    /// someone changes their Home address, every reminder that says "home"
    /// follows it on the next reconcile without any of them being edited.
    static func resolvedPlace(for intent: LocationIntent) -> ResolvedPlace? {
        switch intent.place {
        case .home, .work:
            SavedPlaceStore.place(for: intent.place)?.resolved
        case .currentLocation:
            // "Here" only ever meant a coordinate, captured at the moment it was
            // said. There is nothing to re-resolve against.
            intent.resolvedPlace
        case let .named(name):
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : intent.resolvedPlace
        }
    }

    private static func missingPlaceBlocker(
        for reference: PlaceReference
    ) -> LocationReminderBlocker {
        switch reference {
        case .home: .missingHome
        case .work: .missingWork
        case .currentLocation: .locationUnavailable
        case let .named(name):
            // An empty name means the sentence named a place the parser could
            // not read, which is a different problem from a name that simply
            // has not been searched for yet.
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .placeNotFound
                : .ambiguousPlace
        }
    }
}
