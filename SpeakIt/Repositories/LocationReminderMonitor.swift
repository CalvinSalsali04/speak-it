import CoreLocation
import Foundation
import UserNotifications

/// One location reminder, reduced to what monitoring actually needs.
struct LocationMonitorRequest: Equatable, Sendable {
    let itemID: UUID
    let title: String
    let event: LocationEvent
    let place: ResolvedPlace
    let repeats: Bool
}

/// Why a particular item is not being monitored, alongside the ones that are.
struct LocationMonitorReconciliation: Equatable, Sendable {
    var monitored: [UUID] = []
    var blocked: [UUID: LocationReminderBlocker] = [:]
}

/// Keeps CoreLocation's monitored regions in step with the saved reminders.
///
/// The exact counterpart of what `ReminderScheduler` does for notifications, and
/// for the same reason: two stores that can drift — SwiftData and CoreLocation —
/// are reconciled by rebuilding one from the other, rather than by trying to
/// keep every mutation paired. A crash between saving and monitoring, a
/// permission revoked in Settings, a region orphaned by an edit, a reminder
/// deleted while the app was closed: all of them are repaired by the same
/// foreground pass, without the app needing to know which one happened.
///
/// Permission is never persisted. It is read here, at reconcile time, and an
/// item that cannot be monitored is *reported* as blocked rather than deleted or
/// disabled. The reminder still means what it meant.
@MainActor
final class LocationReminderMonitor: NSObject {
    /// iOS monitors at most 20 regions per app, and that budget is shared with
    /// anything else the app might register. Staying under it deliberately
    /// leaves headroom rather than discovering the limit by failing.
    static let regionBudget = 18

    static let shared = LocationReminderMonitor()

    private let manager: CLLocationManager
    private var lastReconciliation = LocationMonitorReconciliation()

    /// Set by the app so an entered region can be turned into a notification.
    var onRegionEvent: ((UUID, LocationEvent) -> Void)?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: Authorization

    /// The device's current ability to monitor places. Always queried, never
    /// stored — see `LocationAuthorization`.
    var authorization: LocationAuthorization {
        let status: LocationAuthorization.Status = switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .notDetermined
        }
        return LocationAuthorization(
            status: status,
            isPrecise: manager.accuracyAuthorization == .fullAccuracy,
            isRegionMonitoringAvailable: CLLocationManager.isMonitoringAvailable(
                for: CLCircularRegion.self
            )
        )
    }

    /// Whether the Always prompt has already been shown once.
    ///
    /// iOS presents the Always upgrade prompt **once per install**. Every later
    /// `requestAlwaysAuthorization()` returns silently, so a button wired
    /// straight to it becomes a button that visibly does nothing. Recording that
    /// the ask has happened is the only way to know to send the person to
    /// Settings instead.
    ///
    /// This records what *the app asked*, not what the system granted — it is
    /// not a cached permission, and `LocationAuthorization` is still queried
    /// fresh every time.
    private(set) var hasRequestedAlwaysAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: Self.alwaysRequestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alwaysRequestedKey) }
    }

    private static let alwaysRequestedKey = "SpeakIt.location.hasRequestedAlways"

    /// The next step available to unblock background place reminders.
    enum AuthorizationStep: Equatable {
        /// Never asked. One tap shows the first system prompt.
        case requestWhenInUse
        /// Granted foreground access; Always has not been asked for yet. This is
        /// the moment to explain why a reminder needs background access.
        case requestAlways
        /// Asked already, and iOS will not show that prompt again. Only Settings
        /// can change it now.
        case openSettings
        /// Nothing to ask for.
        case none
    }

    var authorizationStep: AuthorizationStep {
        switch manager.authorizationStatus {
        case .notDetermined: .requestWhenInUse
        case .authorizedWhenInUse: hasRequestedAlwaysAuthorization ? .openSettings : .requestAlways
        case .denied, .restricted: .openSettings
        case .authorizedAlways: authorization.isPrecise ? .none : .openSettings
        @unknown default: .openSettings
        }
    }

    /// Asks for the access a place reminder needs, one step at a time.
    ///
    /// Two steps on purpose, and in this order because iOS enforces it: Always
    /// can only be granted after When In Use, and asking for it from a cold
    /// start is both refused more often and more alarming. Setting Home or
    /// capturing "here" never comes through here — those need only a single
    /// foreground fix and use `CurrentLocationProvider`, which asks for When In
    /// Use and nothing more. The Always prompt belongs to the one action that
    /// genuinely needs the app woken while closed: arming a place reminder.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Recorded before the call, so a prompt the person swipes away
            // still counts as spent. It is spent either way.
            hasRequestedAlwaysAuthorization = true
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: Reconciliation

    /// Rebuilds the monitored set from the requests that should be monitored.
    ///
    /// Idempotent, like its notification counterpart, because it runs on every
    /// foreground and after every mutation. Regions no longer backed by a
    /// request are always stopped first, so an edited or deleted reminder cannot
    /// leave a region behind that still fires.
    @discardableResult
    func reconcile(_ requests: [LocationMonitorRequest]) -> LocationMonitorReconciliation {
        var result = LocationMonitorReconciliation()
        let authorization = self.authorization

        // Stop everything this app owns that no longer has a live request. Done
        // before any permission check, so revoking access still cleans up.
        let wanted = Set(requests.map { Self.regionIdentifier(for: $0) })
        for region in manager.monitoredRegions where Self.isSpeakItRegion(region.identifier) {
            if !wanted.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
        }

        guard let blocker = authorization.blocker else {
            return startMonitoring(requests, into: &result)
        }

        // Not authorized: nothing is monitored, and every reminder is reported
        // with the reason rather than being quietly dropped.
        for region in manager.monitoredRegions where Self.isSpeakItRegion(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for request in requests {
            result.blocked[request.itemID] = blocker
        }
        lastReconciliation = result
        return result
    }

    private func startMonitoring(
        _ requests: [LocationMonitorRequest],
        into result: inout LocationMonitorReconciliation
    ) -> LocationMonitorReconciliation {
        // The budget is finite, so the overflow has to be chosen rather than
        // discovered. Repeating reminders are kept first: a one-shot that misses
        // its region can still be completed by hand, while a repeating one that
        // stops being monitored is silently broken forever.
        let ordered = requests.sorted { lhs, rhs in
            lhs.repeats == rhs.repeats
                ? lhs.itemID.uuidString < rhs.itemID.uuidString
                : lhs.repeats
        }

        for (index, request) in ordered.enumerated() {
            guard index < Self.regionBudget else {
                result.blocked[request.itemID] = .monitoringLimitReached
                continue
            }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(
                    latitude: request.place.latitude,
                    longitude: request.place.longitude
                ),
                radius: request.place.radius,
                identifier: Self.regionIdentifier(for: request)
            )
            // Only the event that was asked for. Monitoring both and filtering
            // later would wake the app for arrivals it was never asked about.
            region.notifyOnEntry = request.event == .arrive
            region.notifyOnExit = request.event == .leave
            manager.startMonitoring(for: region)
            result.monitored.append(request.itemID)
        }
        lastReconciliation = result
        return result
    }

    /// Stops monitoring one item's region immediately, for the mutation paths
    /// that already know exactly what changed.
    func stopMonitoring(itemID: UUID) {
        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.regionPrefix + itemID.uuidString) {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: Identifiers

    private static let regionPrefix = "SpeakIt.place."

    /// Encodes the item and the event, so changing "arrive" to "leave" produces
    /// a different region and the old one is reconciled away rather than
    /// silently reused with the wrong trigger.
    static func regionIdentifier(for request: LocationMonitorRequest) -> String {
        "\(regionPrefix)\(request.itemID.uuidString).\(request.event.rawValue)"
    }

    static func itemID(fromRegionIdentifier identifier: String) -> UUID? {
        guard isSpeakItRegion(identifier) else { return nil }
        let body = identifier.dropFirst(regionPrefix.count)
        return UUID(uuidString: String(body.prefix(36)))
    }

    static func isSpeakItRegion(_ identifier: String) -> Bool {
        identifier.hasPrefix(regionPrefix)
    }
}

extension LocationReminderMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        Task { @MainActor in
            guard let itemID = Self.itemID(fromRegionIdentifier: region.identifier) else { return }
            self.onRegionEvent?(itemID, .arrive)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        Task { @MainActor in
            guard let itemID = Self.itemID(fromRegionIdentifier: region.identifier) else { return }
            self.onRegionEvent?(itemID, .leave)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Permission changed under us. The reminders have not changed meaning,
        // so nothing is deleted — the app is simply told to reconcile again.
        Task { @MainActor in
            NotificationCenter.default.post(
                name: LocationReminderMonitor.authorizationDidChangeNotification,
                object: nil
            )
        }
    }
}

extension LocationReminderMonitor {
    static let authorizationDidChangeNotification = Notification.Name(
        "SpeakIt.locationAuthorizationDidChange"
    )
}
