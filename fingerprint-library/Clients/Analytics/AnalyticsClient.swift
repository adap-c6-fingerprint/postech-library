import ComposableArchitecture
import Foundation

/// 분석 이벤트 기록과 앱 수명에 맞춘 분석·세션 리플레이 런타임 제어.
nonisolated struct AnalyticsClient: Sendable {
    var record: @Sendable (AnalyticsEvent) -> Void
    /// 앱이 활성·비활성으로 바뀐 것을 분석과 세션 리플레이에 알린다.
    var setActive: @Sendable (Bool) async -> Void = { _ in }
    /// 활성 중 주기적으로 쌓인 이벤트를 저장한다.
    var checkpoint: @Sendable () -> Void = {}
    /// 프로필(소속·관심 분야)과 동의 상태를 분석 속성에 반영한다.
    var updateProfile: @Sendable (UserProfile?) -> Void = { _ in }
    /// 사용자가 분석·리플레이 동의를 바꿀 때마다 알린다.
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
