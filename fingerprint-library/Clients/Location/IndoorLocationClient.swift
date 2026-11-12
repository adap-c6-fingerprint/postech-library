import ComposableArchitecture
import Foundation

nonisolated struct IndoorLocationClient: Sendable {
    var events: @Sendable () async -> AsyncStream<IndoorLocationEvent>
    var requestPermission: @Sendable () async -> Void
}

extension IndoorLocationClient: DependencyKey {
    static let liveValue = Self(
        // 등록된 실내 측위를 CoreLocation으로 받는다. 실내에서는 좌표와 함께 층(CLFloor.level)이 온다.
        events: { await LiveIndoorLocationProvider.shared.events() },
        requestPermission: {
            // 위치 공급자와 별개로 홈 진입 시 시스템 권한을 요청한다.
            // 실제 권한이 미결정일 때만 Provider가 팝업을 표시한다.
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
