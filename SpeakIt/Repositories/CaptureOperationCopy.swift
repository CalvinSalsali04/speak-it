import Foundation

/// The words shown after an operation, so the confirmation describes what
/// actually happened.
///
/// "Remembered" after a cancellation is the app narrating the wrong action, and
/// it is exactly the kind of small mismatch that makes a person stop trusting a
/// voice interface — they said cancel, the screen said remembered, and now they
/// do not know which one is true.
enum CaptureOperationCopy {
    struct Copy: Equatable {
        let title: String
        let detail: String
        let symbol: String
    }

    static func make(for outcome: CaptureOperationOutcome) -> Copy {
        switch outcome {
        case let .performed(operation, _, title):
            switch operation {
            case .cancel:
                return Copy(title: "Cancelled", detail: title, symbol: "bell.slash")
            case .complete:
                return Copy(title: "Completed", detail: title, symbol: "checkmark.circle")
            case .reschedule:
                return Copy(title: "Rescheduled", detail: title, symbol: "calendar.badge.clock")
            case .create, .retract:
                return Copy(title: "Done", detail: title, symbol: "checkmark")
            }

        case .retracted:
            return Copy(title: "Discarded", detail: "Nothing was saved", symbol: "arrow.uturn.backward")

        case let .notFound(operation, target):
            let what = switch operation {
            case .complete: "complete"
            case .reschedule: "move"
            default: "cancel"
            }
            return Copy(
                title: "Couldn't find that",
                detail: "Nothing to \(what) matching “\(target)”",
                symbol: "questionmark.circle"
            )

        case let .ambiguous(_, candidateIDs):
            return Copy(
                title: "Which one?",
                detail: candidateIDs.count > 1
                    ? "\(candidateIDs.count) items match — choose in Needs review"
                    : "Confirm in Needs review",
                symbol: "list.bullet"
            )

        case .needsConfirmation:
            return Copy(
                title: "Confirm first",
                detail: "That affects everything — confirm in Needs review",
                symbol: "exclamationmark.triangle"
            )
        }
    }
}
