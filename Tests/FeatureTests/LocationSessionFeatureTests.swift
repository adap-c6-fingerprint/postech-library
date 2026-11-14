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

    private func isolatedState() -> LocationSessionFeature.State {
        let state = LocationSessionFeature.State()
        // 매개변수 테스트가 동시에 실행되어도 각 세션의 공유 위치는 독립적이다.
        state.$location = Shared(value: IndoorLocationSnapshot())
        return state
    }

    @Test func 받은_위치_이벤트를_공유_위치_상태에_반영한다() async {
        let events: [IndoorLocationEvent] = [.authorization(.authorized(precise: true)), .position(position)]
        let store = TestStore(initialState: isolatedState()) {
            LocationSessionFeature()
        } withDependencies: {
            $0.indoorLocationClient.events = {
                AsyncStream { continuation in
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off
        await store.send(.started) { $0.isActive = true }
        await store.receive(\.locationEvent, .authorization(.authorized(precise: true)))
        await store.receive(\.locationEvent, .position(position))
        #expect(store.state.location.authorization == .authorized(precise: true))
        #expect(store.state.location.position == position)
    }

    @Test func 앱이_비활성이_되면_구독을_멈추고_다시_활성이면_새로_구독한다() async {
        let (stream, continuation) = AsyncStream.makeStream(of: IndoorLocationEvent.self)
        let store = TestStore(initialState: isolatedState()) {
            LocationSessionFeature()
        } withDependencies: {
            $0.indoorLocationClient.events = { stream }
        }
        await store.send(.started) { $0.isActive = true }
        await store.send(.sceneActiveChanged(false)) { $0.isActive = false }
        continuation.yield(.position(position))
        await store.send(.started) { $0.isActive = true }
        continuation.finish()
        await store.finish()
        #expect(store.state.location.position == nil)
    }

    private func position(at seconds: Double, floor: Int?, source: IndoorPosition.Source = .sensor,
                          heading: Double? = nil) -> IndoorPosition {
        IndoorPosition(coordinate: position.coordinate, floorOrdinal: floor, horizontalAccuracy: 3,
                       timestamp: Date(timeIntervalSinceReferenceDate: seconds), source: source, headingDegrees: heading)
    }

    @Test func 짧은_층_누락은_유지하고_오래_누락되면_알_수_없음으로_전달한다() async {
        let store = TestStore(initialState: isolatedState()) { LocationSessionFeature() }
        store.exhaustivity = .off
        await store.send(.locationEvent(.position(position(at: 10, floor: 2))))
        let missing = position(at: 11, floor: nil, heading: 90)
        await store.send(.locationEvent(.position(missing)))
        #expect(store.state.location.position == missing.replacingFloor(2))
        #expect(store.state.floorEstimator.estimate(at: missing.timestamp).basis == .held)
        await store.send(.locationEvent(.position(position(at: 21, floor: nil))))
        #expect(store.state.location.position?.floorOrdinal == nil)
    }

    @Test(arguments: [IndoorPosition.Source.manual, .replay])
    func 사용자가_지정하거나_재생한_층은_추정기로_바꾸지_않는다(source: IndoorPosition.Source) async {
        let store = TestStore(initialState: isolatedState()) { LocationSessionFeature() }
        store.exhaustivity = .off
        await store.send(.locationEvent(.position(position(at: 10, floor: 2))))
        let estimator = store.state.floorEstimator
        let chosen = position(at: 11, floor: 4, source: source)
        await store.send(.locationEvent(.position(chosen)))
        #expect(store.state.location.position == chosen)
        #expect(store.state.floorEstimator == estimator)
    }

    @Test func 기압으로_계단_이동을_반영하고_지연된_층으로_되돌아가지_않는다() async {
        let store = TestStore(initialState: isolatedState()) { LocationSessionFeature() }
        store.exhaustivity = .off
        await store.send(.started)
        await store.send(.locationEvent(.authorization(.authorized(precise: true))))
        for second in 0..<120 {
            let time = Double(second) + 0.4
            let height = 18 - 4.5 * min(1, max(0, (time - 25) / 10))
            let sample = BarometerSample(kilopascals: 101.325 * pow(1 - (60 + height) / 44_330.8, 1 / 0.190263),
                                         timestamp: Date(timeIntervalSinceReferenceDate: time))
            let previousPosition = store.state.location.position
            await store.send(.barometerSample(sample))
            #expect(store.state.location.position == previousPosition)
            let raw = position(at: Double(second) + 0.6, floor: second < 54 ? 4 : 3, heading: 90)
            await store.send(.locationEvent(.position(raw)))
            #expect(store.state.location.position == raw.replacingFloor(second < 33 ? 4 : 3))
        }
        await store.send(.sceneActiveChanged(false))
        await store.finish()
    }

    @Test func 나침반_갱신은_위치의_측정_시각과_층_투표를_연장하지_않는다() async {
        let store = TestStore(initialState: isolatedState()) { LocationSessionFeature() }
        store.exhaustivity = .off
        await store.send(.locationEvent(.position(position(at: 10, floor: 2))))
        let estimator = store.state.floorEstimator
        let headingUpdate = position(at: 10, floor: 2, heading: 180)
        await store.send(.locationEvent(.position(headingUpdate)))
        #expect(store.state.floorEstimator == estimator)
        #expect(store.state.location.position == headingUpdate)
        await store.send(.locationEvent(.position(position(at: 9, floor: 4))))
        #expect(store.state.floorEstimator == estimator)
        #expect(store.state.location.position == headingUpdate)
    }

    @Test(arguments: [false, true])
    func 위치_승인_후에만_기압을_구독하고_권한_해제나_앱_비활성화시_취소한다(background: Bool) async {
        let calls = LockIsolated(0)
        let terminations = LockIsolated(0)
        let sample = BarometerSample(kilopascals: 100, timestamp: Date(timeIntervalSinceReferenceDate: 10))
        let (stream, continuation) = AsyncStream.makeStream(of: BarometerSample.self)
        continuation.onTermination = { _ in terminations.withValue { $0 += 1 } }
        let store = TestStore(initialState: isolatedState()) { LocationSessionFeature() } withDependencies: {
            $0.barometerClient.samples = {
                calls.withValue { $0 += 1 }
                continuation.yield(sample)
                return stream
            }
        }
        store.exhaustivity = .off
        await store.send(.started)
        #expect(calls.value == 0)
        await store.send(.locationEvent(.authorization(.denied)))
        #expect(calls.value == 0)
        await store.send(.locationEvent(.authorization(.authorized(precise: true))))
        await store.receive(\.barometerSample, sample)
        #expect(calls.value == 1)
        await store.send(.locationEvent(.authorization(.authorized(precise: true))))
        #expect(calls.value == 1)
        if background {
            await store.send(.sceneActiveChanged(false))
        } else {
            await store.send(.locationEvent(.authorization(.denied)))
        }
        await store.finish()
        #expect(!store.state.isBarometerActive)
        #expect(terminations.value == 1)
        guard case .terminated = continuation.yield(sample) else {
            Issue.record("취소한 기압 스트림이 표본을 계속 받고 있습니다.")
            return
        }
        let estimator = store.state.floorEstimator
        await store.send(.barometerSample(.init(kilopascals: 99, timestamp: sample.timestamp.addingTimeInterval(1))))
        #expect(store.state.floorEstimator == estimator)
    }
}
