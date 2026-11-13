import ComposableArchitecture
import Foundation

nonisolated struct IndoorLocationClient: Sendable {
    var events: @Sendable () async -> AsyncStream<IndoorLocationEvent>
    var requestPermission: @Sendable () async -> Void
}

extension IndoorLocationClient: DependencyKey {
    static let liveValue = Self(
        events: { await LiveIndoorLocationProvider.shared.events() },
        requestPermission: {
            await LiveIndoorLocationProvider.shared.requestPermission()
        }
    )
    static let testValue = Self(events: { AsyncStream { $0.finish() } }, requestPermission: {})
}

nonisolated extension DependencyValues {
    var indoorLocationClient: IndoorLocationClient {
        get { self[IndoorLocationClient.self] }
        set { self[IndoorLocationClient.self] = newValue }
    }
}
