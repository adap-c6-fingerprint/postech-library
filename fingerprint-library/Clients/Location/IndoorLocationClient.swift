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
                            horizontalAccuracy: position.horizontalAccuracy, timestamp: Date(), source: .replay,
                            headingDegrees: position.headingDegrees
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
    nonisolated static var usesSimulation: Bool {
        #if DEBUG
        return IndoorSimulationSettings.load().usesSimulation(
            environment: ProcessInfo.processInfo.environment
        )
        #else
        return false
        #endif
    }

    static let liveValue = Self(
        events: {
            #if DEBUG
            if usesSimulation { return IndoorSimulationLocationProvider.events() }
            #endif
            return await LiveIndoorLocationProvider.shared.events()
        },
        requestPermission: {
            // 위치 공급자와 별개로 홈 진입 시 시스템 권한을 요청한다.
            // 실제 권한이 미결정일 때만 Provider가 팝업을 표시한다.
            await LiveIndoorLocationProvider.shared.requestPermission()
        }
    )
    static let testValue = Self(events: { AsyncStream { $0.finish() } }, requestPermission: {})
}

extension DependencyValues {
    var indoorLocationClient: IndoorLocationClient {
        get { self[IndoorLocationClient.self] }
        set { self[IndoorLocationClient.self] = newValue }
    }
}
