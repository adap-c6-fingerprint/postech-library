#if DEBUG
import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorSimulationReconnectTests {
        private actor Probe {
            let streams: [AsyncStream<IndoorLocationEvent>]
            var requests = 0
            var cancellations = 0
            init(streams: [AsyncStream<IndoorLocationEvent>]) { self.streams = streams }
            func next() -> AsyncStream<IndoorLocationEvent> {
                defer { requests += 1 }
                return streams[min(requests, streams.count - 1)]
            }
            func cancelled() { cancellations += 1 }
        }

        @Test("화면에서 다시 연결하면 이전 위치·경로를 비우고 기존 스트림을 취소한 뒤 새 위치를 수신한다")
        func reconnectsWithoutRestartingApp() async throws {
            let (first, firstContinuation) = AsyncStream.makeStream(of: IndoorLocationEvent.self)
            let (second, secondContinuation) = AsyncStream.makeStream(of: IndoorLocationEvent.self)
            let probe = Probe(streams: [first, second])
            firstContinuation.onTermination = { _ in Task { await probe.cancelled() } }
            secondContinuation.onTermination = { _ in Task { await probe.cancelled() } }
            var initial = IndoorMapFeature.State()
            initial.map = IndoorMapTestData.map()
            initial.selectedFloorID = IndoorMapTestData.upperID
            initial.isActive = true
            initial.authorization = .authorized(precise: true)
            initial.latestPosition = IndoorMapTestData.position()
            initial.manualPosition = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: 4,
                horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .manual)
            initial.routeError = "이전 위치의 경로 오류"
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
                $0.indoorLocationClient.events = { await probe.next() }
            }
            await store.send(.simulationConnectionChanged) {
                $0.latestPosition = nil
                $0.manualPosition = nil
                $0.authorization = .notDetermined
                $0.locationMessage = "선택한 위치 공급자에 연결하고 있어요."
                $0.routeError = nil
                $0.routeRequestID = 1
            }
            firstContinuation.yield(.authorization(.authorized(precise: true)))
            await store.receive(\.locationEvent) { $0.authorization = .authorized(precise: true) }
            let firstPosition = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: 4,
                horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .simulation)
            firstContinuation.yield(.position(firstPosition))
            await store.receive(\.locationEvent) { $0.latestPosition = firstPosition; $0.locationMessage = nil }
            await store.send(.simulationConnectionChanged) {
                $0.latestPosition = nil
                $0.authorization = .notDetermined
                $0.locationMessage = "선택한 위치 공급자에 연결하고 있어요."
            }
            secondContinuation.yield(.authorization(.authorized(precise: true)))
            await store.receive(\.locationEvent) { $0.authorization = .authorized(precise: true) }
            let nextPosition = IndoorPosition(coordinate: .init(latitude: 36.002, longitude: 129.002),
                floorOrdinal: 4, horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .simulation)
            secondContinuation.yield(.position(nextPosition))
            await store.receive(\.locationEvent) { $0.latestPosition = nextPosition; $0.locationMessage = nil }
            await store.send(.disappeared) { $0.isActive = false }
            await store.finish()
            #expect(await probe.requests == 2)
            for _ in 0..<100 {
                if await probe.cancellations == 2 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await probe.cancellations == 2)
        }
    }
}
#endif
