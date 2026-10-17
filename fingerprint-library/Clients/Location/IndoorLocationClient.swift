import ComposableArchitecture
import Foundation

nonisolated struct IndoorLocationClient: Sendable {
    var events: @Sendable () async -> AsyncStream<IndoorLocationEvent>
    var requestPermission: @Sendable () async -> Void

    /// 실측과 같은 인터페이스로 테스트 위치를 공급하며 센서 위치와 구분한다.
    static func replaying(_ positions: [IndoorPosition], interval: Duration = .seconds(1)) -> Self {
        Self(events: {
            AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
                let task = Task {
                    continuation.yield(.authorization(.authorized(precise: true)))
                    for position in positions {
                        guard !Task.isCancelled else { break }
                        continuation.yield(.position(IndoorPosition(
                            coordinate: position.coordinate, floorOrdinal: position.floorOrdinal,
                            horizontalAccuracy: position.horizontalAccuracy, timestamp: Date(), source: .replay
                        )))
                        do { try await Task.sleep(for: interval) } catch { break }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }, requestPermission: {})
    }
}

extension IndoorLocationClient: DependencyKey {
    static let liveValue = Self(
        events: { await LiveIndoorLocationProvider.shared.events() },
        requestPermission: { await LiveIndoorLocationProvider.shared.requestPermission() }
    )
    static let testValue = Self(events: { AsyncStream { $0.finish() } }, requestPermission: {})
}

extension DependencyValues {
    var indoorLocationClient: IndoorLocationClient {
        get { self[IndoorLocationClient.self] }
        set { self[IndoorLocationClient.self] = newValue }
    }
}
