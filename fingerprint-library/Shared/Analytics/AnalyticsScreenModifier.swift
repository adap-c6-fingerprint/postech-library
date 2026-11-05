import SwiftUI

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: AnalyticsScreen
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { AnalyticsRuntime.shared.showScreen(screen, token: token) }
            .onDisappear { AnalyticsRuntime.shared.hideScreen(token: token) }
    }
}

extension View {
    func analyticsScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen))
    }
}
