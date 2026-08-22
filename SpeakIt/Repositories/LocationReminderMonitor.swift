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
    let triggerRevision: Int

    init(
        itemID: UUID,
        title: String,
        event: LocationEvent,
        place: ResolvedPlace,
        repeats: Bool,
        triggerRevision: Int = 0
    ) {
        self.itemID = itemID
        self.title = title
        self.event = event
        self.place = place
        self.repeats = repeats
        self.triggerRevision = triggerRevision
    }
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
    /// Hardware support does not change while this process is running. Asking
    /// Core Location for it from every SwiftUI row can exceed the framework's
    /// supported call rate and stall the main thread on a long list.
    private let isRegionMonitoringAvailable: Bool
    /// Authorization changes arrive through the delegate below. Keeping the
    /// latest snapshot makes presentation reads cheap while remaining current.
    private var cachedAuthorization: LocationAuthorization
    private var lastReconciliation = LocationMonitorReconciliation()

    /// Regions iOS accepted and then refused, keyed by region identifier.
    ///
    /// `startMonitoring(for:)` is not a function that can fail — it returns
    /// immediately and the refusal, if any, arrives later on
    /// `monitoringDidFailFor`. Without this set, the reconciliation that
    /// registered the region has already reported it as monitored and the person
    /// is looking at a reminder iOS is not watching. Remembering the refusal is
    /// what lets the *next* pass tell the truth about it.
    ///
    /// Deliberately not persisted. A registration failure is a fact about this
    /// run of the app, and the natural retry is the next launch.
    private var failedRegionIdentifiers: Set<String> = []

    /// Set by the app so an entered region can be turned into a notification.
    var onRegionEvent: ((UUID, LocationEvent, Int, String) -> Void)?

    override init() {
        let manager = CLLocationManager()
        let monitoringAvailable = CLLocationManager.isMonitoringAvailable(
            for: CLCircularRegion.self
        )
        self.manager = manager
        isRegionMonitoringAvailable = monitoringAvailable
        cachedAuthorization = Self.authorizationSnapshot(
            from: manager,
            isRegionMonitoringAvailable: monitoringAvailable
        )
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: Authorization

    /// The device's current ability to monitor places. This is a live process
    /// snapshot, refreshed by `locationManagerDidChangeAuthorization`, never
    /// persisted with a thought.
    var authorization: LocationAuthorization {
        cachedAuthorization
    }

    private static func authorizationSnapshot(
        from manager: CLLocationManager,
        isRegionMonitoringAvailable: Bool
    ) -> LocationAuthorization {
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
            isRegionMonitoringAvailable: isRegionMonitoringAvailable
        )
    }

    private func refreshAuthorization() {
        cachedAuthorization = Self.authorizationSnapshot(
            from: manager,
            isRegionMonitoringAvailable: isRegionMonitoringAvailable
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
    /// This records what *the app asked*, not what the system granted. The live
    /// authorization snapshot is refreshed independently by the manager's
    /// delegate whenever the system state changes.
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
        switch authorization.status {
        case .notDetermined: .requestWhenInUse
        case .whenInUse: hasRequestedAlwaysAuthorization ? .openSettings : .requestAlways
        case .denied, .restricted: .openSettings
        case .always: authorization.isPrecise ? .none : .openSettings
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
        let result = Self.plan(
            for: requests,
            authorization: authorization,
            failedRegionIdentifiers: failedRegionIdentifiers
        )
        let keep = Set(
            requests
                .filter { result.monitored.contains($0.itemID) }
                .map { Self.regionIdentifier(for: $0) }
        )

        // Stop everything this app owns that the plan does not keep — an edited
        // or deleted reminder, one pushed out by the budget, one iOS refused,
        // and every region at all when access has been revoked. A region left
        // running for a reminder reported as blocked would make the report a lie.
        for region in manager.monitoredRegions
        where Self.isSpeakItRegion(region.identifier) && !keep.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        var existing: [String: CLCircularRegion] = [:]
        for case let region as CLCircularRegion in manager.monitoredRegions {
            existing[region.identifier] = region
        }

        for request in requests where result.monitored.contains(request.itemID) {
            let identifier = Self.regionIdentifier(for: request)
            // Re-registering a region iOS is already watching is what would cost
            // the person a crossing: it counts as a fresh registration, and a
            // fresh registration made while inside the region produces no entry
            // event. Since reconciliation runs on every foreground, a reminder
            // for the place someone is standing in would quietly reset each time
            // they opened the app.
            //
            // Geometry is checked as well as the identifier. The identifier now
            // carries a rounded geometry fingerprint for stale-callback
            // rejection, while this comparison uses the actual stored doubles
            // and the device-clamped radius to decide whether registration can
            // truly be left untouched.
            if let region = existing[identifier], matches(region, request) { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(
                    latitude: request.place.latitude,
                    longitude: request.place.longitude
                ),
                // The hardware has a ceiling on how large a region it will
                // watch, and a region above it is refused outright. Clamping
                // turns "this reminder silently never works" into "this reminder
                // covers as much as the device can watch", which is what the
                // person asked for as nearly as it can be given.
                radius: min(request.place.radius, manager.maximumRegionMonitoringDistance),
                identifier: identifier
            )
            // Only the event that was asked for. Monitoring both and filtering
            // later would wake the app for arrivals it was never asked about.
            region.notifyOnEntry = request.event == .arrive
            region.notifyOnExit = request.event == .leave
            manager.startMonitoring(for: region)
        }

        lastReconciliation = result
        return result
    }

    /// Which reminders may be watched, and why each of the rest may not.
    ///
    /// Pure on purpose. Everything decided here — permission, refused regions,
    /// the budget and who loses it — is policy the app has to be right about on
    /// a device whose authorization the tests cannot grant. Keeping the decision
    /// separate from the CoreLocation calls that carry it out means the policy
    /// can be tested for any authorization, on any machine, rather than only on
    /// a device where somebody has already tapped Allow.
    static func plan(
        for requests: [LocationMonitorRequest],
        authorization: LocationAuthorization,
        failedRegionIdentifiers: Set<String> = []
    ) -> LocationMonitorReconciliation {
        var result = LocationMonitorReconciliation()

        // Not authorized: nothing is monitored, and every reminder is reported
        // with the reason rather than being quietly dropped.
        if let blocker = authorization.blocker {
            for request in requests {
                result.blocked[request.itemID] = blocker
            }
            return result
        }

        // The budget is finite, so the overflow has to be chosen rather than
        // discovered. Repeating reminders are kept first: a one-shot that misses
        // its region can still be completed by hand, while a repeating one that
        // stops being monitored is silently broken forever.
        let ordered = requests.sorted { lhs, rhs in
            lhs.repeats == rhs.repeats
                ? lhs.itemID.uuidString < rhs.itemID.uuidString
                : lhs.repeats
        }

        // A region iOS already refused is reported before the budget is counted,
        // not after. Letting it consume a slot would block a reminder that could
        // have been monitored in favour of one that demonstrably cannot be.
        var monitorable: [LocationMonitorRequest] = []
        for request in ordered {
            if failedRegionIdentifiers.contains(regionIdentifier(for: request)) {
                result.blocked[request.itemID] = .monitoringFailed
            } else {
                monitorable.append(request)
            }
        }

        for (index, request) in monitorable.enumerated() {
            if index < regionBudget {
                result.monitored.append(request.itemID)
            } else {
                result.blocked[request.itemID] = .monitoringLimitReached
            }
        }
        return result
    }

    /// Forgets every recorded registration failure, so the next reconcile tries
    /// them again.
    ///
    /// Called from the moments that are a genuine second chance — a foreground,
    /// an authorization change — and deliberately *not* from the reconcile that
    /// a failure itself triggers, which would spin failure into retry into
    /// failure. The common cause is a connection that was missing and may now be
    /// back, so "try again next time the app is opened" is both the right cadence
    /// and the one the blocker copy promises.
    func clearMonitoringFailures() {
        failedRegionIdentifiers.removeAll()
    }

    /// Records that iOS refused one of this app's regions, and asks for a
    /// reconcile so the refusal reaches the person rather than staying here.
    func recordMonitoringFailure(regionIdentifier: String) {
        guard Self.isSpeakItRegion(regionIdentifier) else { return }
        failedRegionIdentifiers.insert(regionIdentifier)
        NotificationCenter.default.post(
            name: Self.monitoringDidFailNotification,
            object: nil
        )
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

    /// Encodes the item, event, and trigger revision. The revision makes a late
    /// callback from a stopped region distinguishable from the reminder that
    /// replaced it, even when both revisions use the same direction.
    static func regionIdentifier(for request: LocationMonitorRequest) -> String {
        // A saved Home/Work can move without changing the stored intent. Carrying
        // the resolved geometry makes a late callback from the old address stale
        // even though its item and trigger revision are otherwise unchanged.
        let latitude = Int((request.place.latitude * 1_000_000).rounded())
        let longitude = Int((request.place.longitude * 1_000_000).rounded())
        let radius = Int(request.place.radius.rounded())
        return "\(regionPrefix)\(request.itemID.uuidString).\(request.event.rawValue).r\(request.triggerRevision).g\(latitude)_\(longitude)_\(radius)"
    }

    static func eventDetails(
        fromRegionIdentifier identifier: String
    ) -> (itemID: UUID, event: LocationEvent, triggerRevision: Int)? {
        guard isSpeakItRegion(identifier) else { return nil }
        let body = identifier.dropFirst(regionPrefix.count)
        let components = body.split(separator: ".")
        guard components.count >= 2,
              let itemID = UUID(uuidString: String(components[0])),
              let event = LocationEvent(rawValue: String(components[1])) else { return nil }

        // Regions created before revisions were introduced carry no third
        // component. Their stored intents decode to revision zero, so treating
        // them as r0 preserves an in-flight reminder across the upgrade.
        let revision = components.count >= 3
            ? Int(components[2].dropFirst()) ?? 0
            : 0
        return (itemID, event, revision)
    }

    static func itemID(fromRegionIdentifier identifier: String) -> UUID? {
        eventDetails(fromRegionIdentifier: identifier)?.itemID
    }

    static func isSpeakItRegion(_ identifier: String) -> Bool {
        identifier.hasPrefix(regionPrefix)
    }

    /// Whether a region iOS is already watching is the one this request wants.
    ///
    /// Compared with a tolerance rather than exactly: these coordinates have
    /// been through a stored JSON blob and back, and a region that is a
    /// millimetre off is the same region. Insisting on bit equality would
    /// re-register everything on every foreground, which is the precise thing
    /// this check exists to avoid.
    private func matches(_ region: CLCircularRegion, _ request: LocationMonitorRequest) -> Bool {
        let tolerance = 1e-7
        return abs(region.center.latitude - request.place.latitude) < tolerance
            && abs(region.center.longitude - request.place.longitude) < tolerance
            && abs(region.radius - min(request.place.radius, manager.maximumRegionMonitoringDistance)) < 1
            && region.notifyOnEntry == (request.event == .arrive)
            && region.notifyOnExit == (request.event == .leave)
    }
}

extension LocationReminderMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        Task { @MainActor in
            guard let details = Self.eventDetails(fromRegionIdentifier: region.identifier),
                  details.event == .arrive else { return }
            self.onRegionEvent?(
                details.itemID,
                .arrive,
                details.triggerRevision,
                region.identifier
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        Task { @MainActor in
            guard let details = Self.eventDetails(fromRegionIdentifier: region.identifier),
                  details.event == .leave else { return }
            self.onRegionEvent?(
                details.itemID,
                .leave,
                details.triggerRevision,
                region.identifier
            )
        }
    }

    /// iOS refused a region after accepting the call to monitor it.
    ///
    /// The failure is recorded rather than retried on the spot: retrying
    /// immediately would hammer whatever refused it, and the usual reason —
    /// no network reachability, or more regions than the device will take — does
    /// not resolve in the milliseconds an immediate retry would allow. Asking
    /// for a reconcile instead means the person sees the reminder marked as not
    /// being watched, which is the fact.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: any Error
    ) {
        Task { @MainActor in
            guard let identifier = region?.identifier else { return }
            self.recordMonitoringFailure(regionIdentifier: identifier)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Permission changed under us. The reminders have not changed meaning,
        // so nothing is deleted — the app is simply told to reconcile again.
        Task { @MainActor in
            self.refreshAuthorization()
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

    /// A region was refused, so what the app believes it is monitoring is now
    /// wrong and needs rebuilding.
    static let monitoringDidFailNotification = Notification.Name(
        "SpeakIt.locationMonitoringDidFail"
    )
}
