import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationFeatureTests {
    private typealias F = NavigationGuidanceTestFixture

    @Test("세션·방문 순서는 보존하고 실제 위치가 들어오기 전에는 거리·안내를 만들지 않는다")
    func preservesSession() throws {
        let session = try F.session()
        let state = BookNavigationFeature.State(session: session)
        #expect(state.session == session)
        #expect(state.currentStop == session.stops[0])
        #expect(state.currentRoute == session.legs[0])
        #expect(state.currentPlan != nil)
        #expect(state.latestPosition == nil && state.instructionText == nil && state.remainingMeters == nil)
    }

    @Test("위치 이벤트만으로 지도 좌표·회전 안내·남은 거리가 함께 갱신된다")
    func updatesFromLocation() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let original = store.state.session
        let start = F.position(x: 0)
        await store.send(.locationEvent(subscriptionID: 0, .position(start)))
        #expect(store.state.latestPosition == start)
        #expect(store.state.progress?.maneuver == .left)
        #expect(abs((store.state.remainingMeters ?? 0) - 40) < 0.01)
        #expect(store.state.instructionText?.contains("좌회전") == true)
        store.dependencies.date.now = F.now.addingTimeInterval(2)
        let next = F.position(x: 5, seconds: 2)
        await store.send(.locationEvent(subscriptionID: 0, .position(next)))
        #expect(store.state.latestPosition == next)
        #expect(abs((store.state.remainingMeters ?? 0) - 35) < 0.01)
        #expect(store.state.session == original && store.state.currentStopIndex == 0)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("아무 이벤트 없이 10초가 지나도 만료 처리하고 이전 위치가 안내를 되살리지 못한다")
    func expiresSilentlyStoppedLocation() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let position = F.position(x: 0)
        await store.send(.locationEvent(subscriptionID: 0, .position(position)))
        store.dependencies.date.now = F.now.addingTimeInterval(10)
        await clock.advance(by: .seconds(10))
        await store.receive(.locationExpired(subscriptionID: 0, timestamp: position.timestamp))
        #expect(store.state.progress == nil && store.state.remainingMeters == nil)
        #expect(store.state.latestPosition == nil && store.state.rawPosition == nil)
        await store.send(.locationEvent(subscriptionID: 0, .position(position)))
        #expect(store.state.progress == nil)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("새 위치가 만료 타이머를 교체하고 옛 타이머의 응답은 무시한다")
    func replacesExpiry() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let old = F.position(x: 0)
        await store.send(.locationEvent(subscriptionID: 0, .position(old)))
        await clock.advance(by: .seconds(5))
        store.dependencies.date.now = F.now.addingTimeInterval(5)
        let fresh = F.position(x: 5, seconds: 5)
        await store.send(.locationEvent(subscriptionID: 0, .position(fresh)))
        await store.send(.locationExpired(subscriptionID: 0, timestamp: old.timestamp))
        #expect(store.state.latestPosition == fresh && store.state.progress != nil)
        await clock.advance(by: .seconds(5))
        #expect(store.state.latestPosition == fresh)
        store.dependencies.date.now = F.now.addingTimeInterval(15)
        await clock.advance(by: .seconds(5))
        await store.receive(.locationExpired(subscriptionID: 0, timestamp: fresh.timestamp))
        #expect(store.state.latestPosition == nil)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("층이 없는 센서 위치는 사용자가 현재 층을 확인하기 전까지 경로의 층으로 가정하지 않는다")
    func requiresFloorConfirmation() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let sample = F.position(x: 5, level: nil)
        let sensor = IndoorPosition(coordinate: sample.coordinate, floorOrdinal: nil,
            horizontalAccuracy: 0, timestamp: sample.timestamp, source: .sensor)
        await store.send(.locationEvent(subscriptionID: 0, .position(sensor)))
        #expect(store.state.progress == nil && store.state.latestPosition == nil)
        #expect(store.state.statusMessage?.contains("층") == true)
        await store.send(.currentFloorConfirmed(99))
        #expect(store.state.confirmedFloorOrdinal == nil)
        await store.send(.currentFloorConfirmed(0))
        #expect(store.state.latestPosition?.floorOrdinal == 0)
        #expect(store.state.showsNativeUserLocation)
        #expect(abs((store.state.remainingMeters ?? 0) - 35) < 0.01)
        store.dependencies.date.now = F.now.addingTimeInterval(1)
        let unknownFloor = IndoorPosition(coordinate: sensor.coordinate, floorOrdinal: 99,
            horizontalAccuracy: 0, timestamp: F.now.addingTimeInterval(1), source: .sensor)
        await store.send(.locationEvent(subscriptionID: 0, .position(unknownFloor)))
        #expect(store.state.canConfirmCurrentFloor && store.state.effectiveFloorOrdinal == 0)
        #expect(store.state.progress != nil)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("위치 단절·부정확한 위치·권한 철회 시 오래된 안내와 위치를 유지하지 않는다")
    func invalidatesGuidance() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0))))
        await store.send(.locationEvent(subscriptionID: 0, .temporarilyUnavailable("연결 단절")))
        #expect(store.state.progress == nil && store.state.latestPosition == nil)
        store.dependencies.date.now = F.now.addingTimeInterval(1)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, seconds: 1))))
        #expect(store.state.progress != nil)
        store.dependencies.date.now = F.now.addingTimeInterval(2)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, accuracy: 50, seconds: 2))))
        #expect(store.state.progress == nil && store.state.latestPosition == nil)
        store.dependencies.date.now = F.now.addingTimeInterval(3)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, seconds: 3))))
        await store.send(.locationEvent(subscriptionID: 0, .authorization(.denied)))
        #expect(!store.state.showsNativeUserLocation)
        #expect(store.state.remainingMeters == nil && store.state.latestPosition == nil)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 1, seconds: 4))))
        #expect(store.state.progress == nil)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("경로 밖에서는 경로·책 순서를 바꾸지 않고 안내를 멈추며 미래 시각의 잘못된 샘플에서 회복한다")
    func offRouteAndFutureTimestamp() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let session = store.state.session
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, y: 20))))
        #expect(store.state.progress == nil && store.state.statusMessage?.contains("벗어") == true)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, seconds: 1_000))))
        #expect(store.state.lastReceivedTimestamp == F.now)
        store.dependencies.date.now = F.now.addingTimeInterval(1)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0, seconds: 1))))
        #expect(store.state.progress != nil)
        #expect(store.state.session == session && store.state.currentStopIndex == 0)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("실제 클라이언트 스트림을 구독하고 화면 이탈·백그라운드에서 취소하며 이전 구독 응답을 무시한다")
    func locationLifecycle() async throws {
        let stream = AsyncStream<IndoorLocationEvent>.makeStream()
        let clock = TestClock()
        let session = try F.session()
        let store = TestStore(initialState: BookNavigationFeature.State(session: session)) {
            BookNavigationFeature()
        } withDependencies: {
            $0.indoorLocationClient.events = { stream.stream }
            $0.indoorLocationClient.requestPermission = {}
            $0.date.now = F.now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.task)
        await store.send(.task)
        #expect(store.state.subscriptionID == 1)
        stream.continuation.yield(.authorization(.authorized(precise: true)))
        await store.receive(.locationEvent(subscriptionID: 1, .authorization(.authorized(precise: true))))
        let sample = F.position(x: 0)
        stream.continuation.yield(.position(sample))
        await store.receive(.locationEvent(subscriptionID: 1, .position(sample)))
        #expect(store.state.progress != nil)
        await store.send(.sceneActiveChanged(false))
        #expect(!store.state.isActive && store.state.latestPosition == nil)
        await store.send(.locationEvent(subscriptionID: 1, .position(F.position(x: 1, seconds: 1))))
        #expect(store.state.progress == nil)
        await store.send(.sceneActiveChanged(true))
        #expect(store.state.subscriptionID == 2)
        await store.send(.locationEvent(subscriptionID: 1, .position(F.position(x: 2, seconds: 2))))
        #expect(store.state.progress == nil)
        await store.send(.disappeared)
        #expect(!store.state.isActive)
        await store.finish()
    }

    @Test("도착점 근처에서도 자동 화면 전환·다음 책 진행 없이 수동 확인으로 기존 도착 화면을 연다")
    func manualArrival() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 20, y: 20))))
        #expect(store.state.progress?.maneuver == .nearDestination)
        #expect(!store.state.isArrivalPresented && store.state.currentStopIndex == 0)
        await store.send(.arrivalTestTapped)
        #expect(store.state.isArrivalPresented)
        await store.send(.arrivalPresentationChanged(false))
        #expect(!store.state.isArrivalPresented && store.state.currentStopIndex == 0)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("범위 밖 목적지 인덱스에서는 안내·도착 진입을 막는다", arguments: [-1, 2])
    func invalidStopIndex(_ index: Int) async throws {
        var state = BookNavigationFeature.State(session: try F.session())
        state.currentStopIndex = index
        #expect(state.currentStop == nil && state.currentRoute == nil && state.currentPlan == nil)
        let store = TestStore(initialState: state) { BookNavigationFeature() }
        await store.send(.arrivalTestTapped)
        await store.send(.arrivalPresentationChanged(true))
    }

    @Test("취소 팝업을 닫으면 안내를 유지하고 확인하면 위치 구독·만료를 끊고 재시작을 막는다")
    func cancellationFlow() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let session = store.state.session
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0))))
        let progress = store.state.progress
        await store.send(.cancelTapped)
        #expect(store.state.isCancelConfirmationPresented && store.state.exitReason == nil)
        await store.send(.cancelDismissed)
        #expect(store.state.isActive && store.state.progress == progress)
        // Alert 바인딩이 먼저 false가 된 순서에서도 확인 버튼이 안내를 종료한다.
        await store.send(.cancelConfirmed)
        #expect(store.state.exitReason == .cancelled && !store.state.isActive)
        #expect(store.state.progress == nil && store.state.latestPosition == nil)
        #expect(!store.state.isCancelConfirmationPresented && !store.state.isArrivalPresented)
        #expect(store.state.currentTurnArrows.isEmpty)
        await store.send(.task)
        await store.send(.sceneActiveChanged(true))
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 1, seconds: 1))))
        #expect(!store.state.isActive && store.state.latestPosition == nil)
        #expect(store.state.session == session)
        await clock.advance(by: .seconds(20))
        await store.finish()
    }

    @Test("다음 책 진행 시 제목·서가·청구기호·경로·지도 화살표가 함께 바뀌고 중복 탭은 건너뛰지 않는다")
    func advancesAllCurrentBookInformation() async throws {
        let clock = TestClock()
        let session = try BookNavigationDetailsTestFixture.session()
        var initial = BookNavigationFeature.State(session: session)
        initial.isActive = true
        initial.authorization = .authorized(precise: true)
        let store = TestStore(initialState: initial) { BookNavigationFeature() } withDependencies: {
            $0.date.now = F.now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        #expect(store.state.currentBookInfo?.callNumbers == ["QA42 .A1 2020"])
        #expect(store.state.currentTurnArrows.first?.maneuver == .left)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 20, y: 20, level: 2))))
        #expect(store.state.isApproachingShelf)
        await store.send(.arrivalTestTapped)
        await store.send(.continueFromArrival(stopIndex: 0))
        #expect(store.state.currentStopIndex == 1 && !store.state.isArrivalPresented)
        #expect(store.state.currentBookInfo?.book == session.stops[1].book)
        #expect(store.state.currentBookInfo?.shelf.realNumber == "368")
        #expect(store.state.currentBookInfo?.callNumbers == ["QA150 .B1 2021"])
        #expect(store.state.currentRoute == session.legs[1])
        #expect(store.state.progress?.maneuver == .right)
        #expect(store.state.currentTurnArrows.first?.maneuver == .right)
        #expect(store.state.cameraRequest.id > initial.cameraRequest.id)
        #expect(store.state.session == session)
        await store.send(.continueFromArrival(stopIndex: 0))
        await store.send(.finishFromArrival(stopIndex: 1))
        #expect(store.state.currentStopIndex == 1 && store.state.exitReason == nil)
        await store.send(.arrivalTestTapped)
        await store.send(.finishFromArrival(stopIndex: 1))
        #expect(store.state.exitReason == .completed && !store.state.isActive)
        await store.send(.finishFromArrival(stopIndex: 1))
        #expect(store.state.currentStopIndex == 1)
        await store.finish()
    }

    @Test("마지막 책 이전에는 완료할 수 없고 도착 화면에서도 전체 취소를 처리한다")
    func cancelsFromArrival() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        await store.send(.arrivalTestTapped)
        await store.send(.finishFromArrival(stopIndex: 0))
        #expect(store.state.exitReason == nil)
        await store.send(.cancelTapped)
        await store.send(.cancelConfirmed)
        #expect(store.state.exitReason == .cancelled && !store.state.isArrivalPresented)
        await store.finish()
    }

    @Test("위치 이동 버튼만 카메라를 재지정하고 새 위치 샘플이 사용자의 지도 이동을 덮어쓰지 않는다")
    func explicitRecenter() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0))))
        let first = store.state.cameraRequest.id
        await store.send(.recenterTapped)
        #expect(store.state.cameraRequest.id == first + 1)
        #expect(store.state.cameraRequest.target == .position(F.position(x: 0).coordinate))
        store.dependencies.date.now = F.now.addingTimeInterval(1)
        await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 1, seconds: 1))))
        #expect(store.state.cameraRequest.id == first + 1)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test("서가가 가까워도 회전 안내가 남아 있으면 근처 캡슐로 필요한 안내를 가리지 않는다")
    func keepsUpcomingTurnVisibleNearShelf() throws {
        var state = BookNavigationFeature.State(session: try F.session())
        state.latestPosition = F.position(x: 15)
        state.progress = .init(stepIndex: 0, fraction: 0.75, distanceAlongRoute: 15,
            coordinate: F.position(x: 15).coordinate, maneuver: .left, distanceToManeuver: 3, remainingMeters: 6)
        #expect(!state.isApproachingShelf)
        state.progress = .init(stepIndex: 1, fraction: 0.75, distanceAlongRoute: 35,
            coordinate: F.position(x: 20, y: 15).coordinate, maneuver: .straight, distanceToManeuver: 5, remainingMeters: 5)
        #expect(state.isApproachingShelf)
    }

    private func makeStore(clock: TestClock<Duration>) throws -> TestStore<BookNavigationFeature.State, BookNavigationFeature.Action> {
        var initial = BookNavigationFeature.State(session: try F.session())
        initial.isActive = true
        initial.authorization = .authorized(precise: true)
        let store = TestStore(initialState: initial) { BookNavigationFeature() } withDependencies: {
            $0.date.now = F.now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }
}
