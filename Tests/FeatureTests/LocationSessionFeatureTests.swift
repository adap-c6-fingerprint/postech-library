import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct LocationSessionFeatureTests {
    let position = IndoorPosition(
        coordinate: .init(latitude: 36, longitude: 129), floorOrdinal: 2, horizontalAccuracy: 3,
        timestamp: Date(timeIntervalSinceReferenceDate: 10), source: .sensor
    )

    @Test func 받은_위치_이벤트를_공유_위치_상태에_반영한다() async {
        let events: [IndoorLocationEvent] = [.authorization(.authorized(precise: true)), .position(position)]
        let store = TestStore(initialState: LocationSessionFeature.State()) {
            LocationSessionFeature()
        } withDependencies: {
            $0.indoorLocationClient.events = {
                AsyncStream { continuation in
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                }
            }
        }
        // 공유 위치 상태는 참조라 받은 이벤트가 함께 반영된다. 받은 순서와 최종 상태를 확인한다.
        store.exhaustivity = .off
        await store.send(.started) { $0.isActive = true }
        await store.receive(\.locationEvent, .authorization(.authorized(precise: true)))
        await store.receive(\.locationEvent, .position(position))
        #expect(store.state.location.authorization == .authorized(precise: true))
        #expect(store.state.location.position == position)
    }

    @Test func 앱이_비활성이_되면_구독을_멈추고_다시_활성이면_새로_구독한다() async {
        let (stream, continuation) = AsyncStream.makeStream(of: IndoorLocationEvent.self)
        let store = TestStore(initialState: LocationSessionFeature.State()) {
            LocationSessionFeature()
        } withDependencies: {
            $0.indoorLocationClient.events = { stream }
        }
        await store.send(.started) { $0.isActive = true }
        await store.send(.sceneActiveChanged(false)) { $0.isActive = false }
        // 구독을 멈춘 뒤에 온 이벤트는 반영하지 않는다.
        continuation.yield(.position(position))
        await store.send(.started) { $0.isActive = true }
        continuation.finish()
        await store.finish()
        #expect(store.state.location.position == nil)
    }
}
