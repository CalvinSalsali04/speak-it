import Foundation

/// Debug-only hardware QA override. A launch argument pair such as
/// `--location-qa-radius 200` lets the same device/build exercise the radius
/// matrix without shipping a product setting that people should not have to
/// understand. Release builds always use the saved/default value.
private enum LocationQARadius {
    static func resolve(_ proposed: Double) -> Double {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--location-qa-radius"),
           arguments.indices.contains(flag + 1),
           let override = Double(arguments[flag + 1]),
           (100...1_000).contains(override) {
            return override
        }
#endif
        return proposed
    }
}

/// A place the person configures once and refers to by name.
struct SavedPlace: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var radius: Double
    /// The address as the person last confirmed it, so a settings row can show
    /// what "Home" currently means without a network round trip.
    var label: String?
    var updatedAt: Date

    init(
        latitude: Double,
        longitude: Double,
        radius: Double = ResolvedPlace.defaultRadius,
        label: String? = nil,
        updatedAt: Date = .now
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.radius = max(LocationQARadius.resolve(radius), 100)
        self.label = label
        self.updatedAt = updatedAt
    }

    var resolved: ResolvedPlace {
        ResolvedPlace(
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            matchedName: label,
            resolvedAt: updatedAt
        )
    }
}

/// Where Home and Work live.
///
/// Kept beside SwiftData rather than in it, for the same reason `RecurrenceStore`
/// is: this is small, additive, device-scoped configuration, and putting it in
/// the store would mean a schema migration to ship a settings row.
///
/// Changing Home is a resolution change, not an intent change. Every reminder
/// that says `.home` keeps meaning "home" and simply re-resolves, which is the
/// whole reason `PlaceReference` never collapses to coordinates.
@MainActor
enum SavedPlaceStore {
    private static let key = "SpeakIt.savedPlaces.v1"
    private static let suiteName = "group.com.calvinwak.SpeakIt"
    private static var cached: [String: SavedPlace]?

    /// Posted when Home or Work changes, so anything monitoring regions can
    /// re-resolve and reconcile rather than keep watching the old address.
    static let didChangeNotification = Notification.Name("SpeakIt.savedPlacesDidChange")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var records: [String: SavedPlace] {
        get {
            if let cached { return cached }
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: SavedPlace].self, from: data) else {
                cached = [:]
                return [:]
            }
            cached = decoded
            return decoded
        }
        set {
            cached = newValue
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    private static func storageKey(for reference: PlaceReference) -> String? {
        switch reference {
        case .home: "home"
        case .work: "work"
        case .currentLocation, .named: nil
        }
    }

    static func place(for reference: PlaceReference) -> SavedPlace? {
        guard let storageKey = storageKey(for: reference) else { return nil }
        return records[storageKey]
    }

    static func set(_ place: SavedPlace?, for reference: PlaceReference) {
        guard let storageKey = storageKey(for: reference) else { return }
        var values = records
        if let place {
            values[storageKey] = place
        } else {
            values.removeValue(forKey: storageKey)
        }
        records = values
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// The blocker a saved place implies when it has not been configured.
    /// Returns `nil` for references that are not saved places at all.
    static func missingPlaceBlocker(for reference: PlaceReference) -> LocationReminderBlocker? {
        switch reference {
        case .home: place(for: .home) == nil ? .missingHome : nil
        case .work: place(for: .work) == nil ? .missingWork : nil
        case .currentLocation, .named: nil
        }
    }

    // Test support. Mirrors `RecurrenceStore` so a suite can restore whatever
    // the device had before it ran.
    static func snapshot() -> [String: SavedPlace] { records }

    static func restore(_ snapshot: [String: SavedPlace]) {
        records = snapshot
    }
}
