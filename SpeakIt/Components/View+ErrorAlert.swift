import SwiftUI

extension View {
    /// The one alert every repository failure surfaces through. The raw
    /// `localizedDescription` of a storage error is a code, not a sentence
    /// ("The operation couldn't be completed. (SwiftData.SwiftDataError
    /// error 1.)"), so system-shaped messages are replaced with what the
    /// person needs to know: what did not happen, and that nothing they saved
    /// has been lost. Messages the app wrote itself pass through unchanged.
    func repositoryErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "That didn’t go through",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                message.wrappedValue = nil
            }
        } message: {
            Text(RepositoryErrorCopy.userFacing(message.wrappedValue))
        }
    }
}

enum RepositoryErrorCopy {
    /// Plain copy for a failure message that came from the system rather
    /// than from Speak It.
    static let storageFallback =
        "Speak It couldn’t update its storage just now. Everything you already saved is still on this device. Try again in a moment."

    static func userFacing(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Please try again."
        }
        let looksLikeSystemError = raw.contains("SwiftData")
            || raw.contains("NSCocoaErrorDomain")
            || raw.contains("CoreData")
            || raw.hasPrefix("The operation couldn’t be completed")
            || raw.hasPrefix("The operation couldn't be completed")
        return looksLikeSystemError ? storageFallback : raw
    }
}
