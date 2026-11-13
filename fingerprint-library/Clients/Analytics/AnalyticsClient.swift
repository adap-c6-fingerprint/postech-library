import ComposableArchitecture
import Foundation

nonisolated struct AnalyticsClient: Sendable {
    var record: @Sendable (AnalyticsEvent) -> Void
    var setActive: @Sendable (Bool) async -> Void = { _ in }
    var checkpoint: @Sendable () -> Void = {}
    var updateProfile: @Sendable (UserProfile?) -> Void = { _ in }
    var consentChanges: @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
}

extension AnalyticsClient: DependencyKey {
    static let liveValue = Self(
        record: { AnalyticsRuntime.shared.record($0) },
        setActive: { isActive in
            AnalyticsRuntime.shared.setActive(isActive)
            await MainActor.run { SessionReplayRuntime.shared.setActive(isActive) }
        },
        checkpoint: { AnalyticsRuntime.shared.checkpoint() },
        updateProfile: { AnalyticsRuntime.shared.updateProfile($0) },
        consentChanges: {
            AsyncStream { continuation in
                let task = Task {
                    for await _ in NotificationCenter.default.notifications(named: AnalyticsRuntime.consentChanged) {
                        continuation.yield()
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )
    static let testValue = Self(record: { _ in })
}

nonisolated extension DependencyValues {
    var analyticsClient: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
