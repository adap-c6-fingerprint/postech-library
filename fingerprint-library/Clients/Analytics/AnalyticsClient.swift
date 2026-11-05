import ComposableArchitecture
import Foundation

nonisolated struct AnalyticsClient: Sendable {
    var record: @Sendable (AnalyticsEvent) -> Void
}

extension AnalyticsClient: DependencyKey {
    static let liveValue = Self(record: { AnalyticsRuntime.shared.record($0) })
    static let testValue = Self(record: { _ in })
}

extension DependencyValues {
    var analyticsClient: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
