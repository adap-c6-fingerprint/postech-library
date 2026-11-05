import Clarity
import SwiftUI

private struct SessionReplayProtectedModifier: ViewModifier {
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .clarityMask()
            .onAppear { SessionReplayRuntime.shared.protect(token) }
            .onDisappear { SessionReplayRuntime.shared.unprotect(token) }
    }
}

extension View {
    func sessionReplayProtected() -> some View {
        modifier(SessionReplayProtectedModifier())
    }
}
