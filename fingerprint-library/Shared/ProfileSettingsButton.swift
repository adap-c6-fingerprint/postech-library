import SwiftUI

struct ProfileSettingsButton: View {
    let action: (() -> Void)?
    var size: CGFloat?
    @Environment(\.scenePhase) private var scenePhase
    @State private var sequence = ProfileTapSequence()
    @State private var pendingNavigation: Task<Void, Never>?
    @State private var showsSettings = false

    var body: some View {
        LibraryTopBarButton(
            title: "마이페이지", symbol: "person.fill", identifier: "library-top-bar-profile",
            action: tapped, size: size
        )
        .disabled(action == nil)
        .sheet(isPresented: $showsSettings) {
            AnalyticsSettingsView(isFirstChoice: false)
        }
        .onDisappear { cancelSequence() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelSequence() }
        }
    }

    private func tapped() {
        pendingNavigation?.cancel()
        if sequence.register(at: ProcessInfo.processInfo.systemUptime) {
            showsSettings = true
            return
        }
        // 첫 탭으로 화면이 바뀌지 않도록 연속 입력 판별 시간만 기다린다.
        pendingNavigation = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(ProfileTapSequence.interval)) }
            catch { return }
            sequence.reset()
            action?()
        }
    }

    private func cancelSequence() {
        pendingNavigation?.cancel()
        pendingNavigation = nil
        sequence.reset()
    }
}
