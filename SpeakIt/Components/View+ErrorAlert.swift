import SwiftUI

extension View {
    func repositoryErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                message.wrappedValue = nil
            }
        } message: {
            Text(message.wrappedValue ?? "Please try again.")
        }
    }
}
