import CoreLocation
import Foundation

/// A one-shot "where am I right now" lookup.
///
/// Deliberately not part of `LocationReminderMonitor`. That type owns long-lived
/// region monitoring and holds the delegate for it; borrowing that delegate for
/// a transient position request would mean a "use my current location" tap could
/// interleave with a geofence callback. Two jobs, two managers.
///
/// This exists for the two moments the app needs a coordinate *now* rather than
/// a place reference that resolves later:
///
/// 1. "Use my current location" when setting Home or Work.
/// 2. Freezing `"here"` at capture time, where the coordinate *is* the meaning.
///
/// Everything else goes through `PlaceReference`, which stays semantic.
@MainActor
final class CurrentLocationProvider: NSObject {
    enum Failure: LocalizedError, Equatable {
        /// The person declined, or Settings has access turned off.
        case permissionDenied
        /// Granted, but the device could not produce a fix.
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Speak It needs location access to use where you are."
            case .unavailable:
                "Speak It couldn't read your location. Try again in a moment."
            }
        }
    }

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, any Error>?
    /// True while waiting for the person to answer the system prompt, so the
    /// authorization callback knows to start the fix rather than ignore itself.
    private var isAwaitingAuthorization = false

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // A place region is 150m across at its smallest. Asking for the best
        // possible fix would cost battery and time to buy precision that the
        // radius immediately discards.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// How stale a cached fix may be and still mean "here". Long enough to
    /// usually hit, short enough that the person has not walked out of the
    /// region being pinned.
    nonisolated static let maximumFixAge: TimeInterval = 120

    /// How loose a fix may be and still be worth pinning a region on.
    ///
    /// The smallest region Speak It creates is 100m and the default is 150m, so
    /// a fix accurate to worse than this could place the pin outside the very
    /// area it is meant to mark. A reminder anchored to the wrong block is worse
    /// than one that honestly reports it could not be placed.
    nonisolated static let maximumFixAccuracy: CLLocationAccuracy = 100

    /// Whether a fix is good enough to freeze as a place.
    ///
    /// "Cached" has to mean *suitable* cached, not merely present. A location
    /// object exists almost always; a 27-minute-old one accurate to ±1.4km is
    /// not where the person is standing, and accepting it because it was
    /// non-nil would pin the region onto the wrong neighbourhood.
    ///
    /// Static and date-injectable so the thresholds are testable without a
    /// device, and `nonisolated` because the delegate callback that screens a
    /// freshly delivered fix runs off the main actor.
    nonisolated static func isSuitable(_ location: CLLocation, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        // A negative age means a clock change put the fix in the future. Its
        // real age is unknowable, so it is not trusted.
        guard age >= 0, age <= maximumFixAge else { return false }
        // CoreLocation reports a negative accuracy when the value is invalid.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumFixAccuracy else { return false }
        return true
    }

    /// A fix iOS already holds, when it is recent and precise enough to mean
    /// "here".
    ///
    /// For freezing `"here"` a suitable cached fix is preferable to a fresh
    /// request rather than merely cheaper: it is closer in time to the moment
    /// the words were said.
    var recentCoordinate: CLLocationCoordinate2D? {
        guard let location = manager.location,
              Self.isSuitable(location) else { return nil }
        return location.coordinate
    }

    /// The device's current coordinate, asking for access first if it has never
    /// been asked.
    ///
    /// When In Use is enough here. Always is only needed to *monitor* a region
    /// in the background, and asking for it while someone is simply setting
    /// their Home address would be asking for more than the moment justifies.
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        // One in flight at a time. A second tap resolves against the same fix
        // rather than stranding the first continuation.
        if continuation != nil { throw Failure.unavailable }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                isAwaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(Failure.permissionDenied))
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            @unknown default:
                finish(.failure(Failure.unavailable))
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, any Error>) {
        guard let continuation else { return }
        // Cleared before resuming so a delegate callback that arrives during the
        // resume cannot resume the same continuation twice.
        self.continuation = nil
        isAwaitingAuthorization = false
        continuation.resume(with: result)
    }
}

extension CurrentLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // A freshly delivered fix gets the same accuracy floor as a cached one.
        // "Just arrived" is not evidence of "good enough": a first indoor fix
        // can be kilometres wide, and pinning a region on it would be silently
        // wrong rather than visibly unresolved.
        let usable = locations.last(where: { Self.isSuitable($0) })?.coordinate
        Task { @MainActor in
            guard let usable else { return self.finish(.failure(Failure.unavailable)) }
            self.finish(.success(usable))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        Task { @MainActor in
            self.finish(.failure(Failure.unavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Only meaningful while a request is parked on the system prompt.
            // Otherwise this is the app being told about a Settings change it
            // has no outstanding question about.
            guard self.isAwaitingAuthorization else { return }
            switch status {
            case .notDetermined:
                // The prompt is still on screen; keep waiting.
                break
            case .denied, .restricted:
                self.finish(.failure(Failure.permissionDenied))
            case .authorizedWhenInUse, .authorizedAlways:
                self.isAwaitingAuthorization = false
                manager.requestLocation()
            @unknown default:
                self.finish(.failure(Failure.unavailable))
            }
        }
    }
}
