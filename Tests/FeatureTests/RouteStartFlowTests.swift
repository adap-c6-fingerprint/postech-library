import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RouteStartFlowTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func position(latitude: Double = 36.0129766, longitude: Double = 129.3257150,
                          floor: Int? = 2) -> IndoorPosition {
        .init(coordinate: .init(latitude: latitude, longitude: longitude), floorOrdinal: floor,
              horizontalAccuracy: 5, timestamp: now, source: .sensor)
    }

    private func makeState(position: IndoorPosition?, mode: BookRoutePreviewFeature.EntryMode = .direct,
                           authorized: Bool = true) async throws -> BookRoutePreviewFeature.State {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        var state = withDependencies { $0.uuid = .incrementing } operation: {
            BookRoutePreviewFeature.State(books: [BookRoutePreviewSample.book], entryMode: mode)
        }
        state.shelf?.map.map = map
        state.$location.withLock {
            $0 = IndoorLocationSnapshot()
            $0.apply(.authorization(authorized ? .authorized(precise: true) : .denied))
            if let position { $0.apply(.position(position)) }
        }
        return state
    }

    @Test func 소장정보_응답_전에도_20m_밖은_출발점_선택으로_간다() async throws {
        var state = try await makeState(position: position(latitude: 36.0130858, longitude: 129.3259576))
        state.shelf?.holdings[BookRoutePreviewSample.book.id] = .loading
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.startDecision == .needsOrigin(.farOutside))
        #expect(store.state.currentStart == nil)
        #expect(store.state.isPreparingManualOrigin)
        #expect(!store.state.isPermissionAlertPresented)
        #expect(!store.state.showsRouteFailure)
        await store.send(.routeMapAvailabilityChanged(true))
        #expect(store.state.isOriginPickerPresented)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 출발점이_필요한_동안에는_소장정보_API를_호출하지_않는다() async throws {
        let state = try await makeState(position: nil, mode: .preview, authorized: false)
        let calls = LockIsolated(0)
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.bookHoldingsClient.fetch = { _ in calls.withValue { $0 += 1 }; return [] }
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        await store.finish()
        #expect(calls.value == 0)
        #expect(!store.state.hasRequestedHoldings)

        await store.send(.originConfirmed(.init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2))
        await store.receive(\.shelf.loadMissingHoldings)
        await store.receive(\.shelf.holdingsLoaded)
        await store.finish()
        #expect(calls.value == 1)
        #expect(store.state.startDecision == nil)
        #expect(store.state.currentStart?.source == .manual)
    }

    @Test(arguments: [BookRoutePreviewFeature.EntryMode.direct, .preview])
    func 내부_층_미확인은_API_호출_전_출발점_선택으로_이어지고_선택_후_안내한다(mode: BookRoutePreviewFeature.EntryMode) async throws {
        var state = try await makeState(
            position: position(latitude: 36.0127633, longitude: 129.3251348, floor: nil), mode: mode)
        let map = try #require(state.shelf?.map.map)
        state.shelf?.map.shelfLabels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let calls = LockIsolated(0)
        let holding = BookRoutePreviewSample.holding
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
            $0.bookHoldingsClient.fetch = { _ in
                calls.withValue { $0 += 1 }
                return [holding]
            }
            $0.routePlanningClient.plan = { map, labels, start, stops in
                try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
            }
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.startDecision == .needsOrigin(.unknownFloor))
        #expect(store.state.currentStart == nil)
        #expect(!store.state.hasRequestedHoldings)
        #expect(!store.state.isPermissionAlertPresented)
        #expect(!store.state.isLocatingTimerRunning)
        #expect(!store.state.showsRouteFailure)
        #expect(calls.value == 0)

        if mode == .preview { await store.send(.startTapped) }
        await store.send(.routeMapAvailabilityChanged(true))
        #expect(store.state.isOriginPickerPresented)
        #expect(calls.value == 0)
        await store.send(.originConfirmed(.init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2))
        await store.receive(\.shelf.loadMissingHoldings)
        await store.receive(\.shelf.holdingsLoaded)
        await store.receive(\.shelf.resolveLocations)
        await store.receive(\.routeLoaded, timeout: .seconds(10))
        #expect(calls.value == 1)
        #expect(store.state.navigation?.routePlan.start.floorOrdinal == 2)
        #expect(store.state.navigation?.usesManualOrigin == true)
        #expect(store.state.navigation?.startsAtEntrance == false)
        #expect(!store.state.showsRouteFailure)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 위치_없음은_이벤트가_반복되어도_최초_5초만_기다린다() async throws {
        let state = try await makeState(position: nil)
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.startDecision == .locating)
        #expect(!store.state.hasRequestedHoldings)
        await clock.advance(by: .seconds(3))
        await store.send(.locationUpdated)
        await clock.advance(by: .seconds(2))
        await store.receive(\.locatingTimedOut)
        #expect(store.state.startDecision == .needsOrigin(.noPosition))
        #expect(store.state.isPreparingManualOrigin)
        #expect(!store.state.showsRouteFailure)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 화면을_떠나면_위치_대기_타이머를_취소한다() async throws {
        let state = try await makeState(position: nil, mode: .preview)
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        await store.send(.disappeared)
        await clock.advance(by: .seconds(10))
        await store.finish()
        #expect(!store.state.hasLocatingTimedOut)
        #expect(!store.state.isLocatingTimerRunning)
    }

    @Test func 권한_없음은_기존_알림을_유지한다() async throws {
        let state = try await makeState(position: nil, authorized: false)
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.isPermissionAlertPresented)
        #expect(!store.state.hasRequestedHoldings)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 지도가_도착하면_다음_위치_이벤트를_기다리지_않고_판정한다() async throws {
        var state = try await makeState(position: position(), mode: .preview)
        let map = try #require(state.shelf?.map.map)
        state.shelf?.map.map = nil
        state.hasRequestedHoldings = true
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.startDecision == nil)
        await store.send(.shelf(.map(.mapLoaded(map))))
        await store.receive(\.shelf.resolveLocations)
        #expect(store.state.currentStart?.source == .manual)
        #expect(store.state.startNotice != nil)
        await store.finish()
    }

    @Test func 주출입구_미리보기에서_안으로_들어오면_현재_위치로_교체한다() async throws {
        var state = try await makeState(
            position: position(latitude: 36.0129329, longitude: 129.3256179, floor: nil), mode: .preview)
        state.hasRequestedHoldings = true
        state.shelf?.holdings[BookRoutePreviewSample.book.id] = .loading
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off
        await store.send(.locationUpdated)
        #expect(store.state.previewStart?.floorOrdinal == 0)
        #expect(store.state.isPreviewFromEntrance)
        #expect(store.state.startNotice != nil)
        let inside = position(latitude: 36.0127633, longitude: 129.3251348)
        store.state.$location.withLock { $0.apply(.position(inside)) }
        await store.send(.locationUpdated)
        #expect(store.state.previewStart == inside)
        #expect(store.state.startNotice == nil)
        let outside = position(latitude: 36.0129329, longitude: 129.3256179, floor: nil)
        store.state.$location.withLock { $0.apply(.position(outside)) }
        await store.send(.locationUpdated)
        #expect(store.state.previewStart?.source == .manual)
        #expect(store.state.previewStart?.floorOrdinal == 0)
        #expect(store.state.startNotice != nil)
        await store.finish()
    }

    @Test(arguments: [false, true]) func 외부에서_실제_경로를_계산하고_안내를_연다(isFar: Bool) async throws {
        let outside = isFar ? position() : position(latitude: 36.0129329, longitude: 129.3256179, floor: nil)
        var state = try await makeState(position: outside)
        let map = try #require(state.shelf?.map.map)
        state.shelf?.map.shelfLabels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        state.shelf?.holdings[BookRoutePreviewSample.book.id] = .loaded([BookRoutePreviewSample.holding])
        state.hasRequestedHoldings = true
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.continuousClock = clock
            $0.routePlanningClient.plan = { map, labels, start, stops in
                try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
            }
        }
        store.exhaustivity = .off
        await store.send(.shelf(.resolveLocations))
        await store.receive(\.routeLoaded, timeout: .seconds(10))
        #expect(store.state.navigation?.routePlan.start.floorOrdinal == 0)
        #expect(store.state.navigation?.confirmedFloorOrdinal == 0)
        #expect(store.state.navigation?.startNotice != nil)
        #expect(store.state.navigation?.usesManualOrigin == false)
        #expect(store.state.routeError == nil)
        let displayedPlan = store.state.previewPlan
        store.state.$location.withLock { $0.apply(.position(position())) }
        await store.send(.locationUpdated)
        #expect(store.state.navigation != nil)
        #expect(store.state.previewPlan == displayedPlan)
        #expect(store.state.routeError == nil)
        await store.send(.navigation(.presented(.setOriginManuallyTapped)))
        #expect(store.state.navigation == nil)
        #expect(store.state.isPreparingManualOrigin)
        await store.send(.routeMapAvailabilityChanged(true))
        #expect(store.state.isOriginPickerPresented)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 수동_출발점을_확정한_뒤_소장정보가_도착해도_안내_시작_의도를_유지한다() async throws {
        var state = try await makeState(position: position(), mode: .preview)
        let holding = BookRoutePreviewSample.holding
        let map = try #require(state.shelf?.map.map)
        state.shelf?.map.shelfLabels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        state.isStartRequested = true
        state.isOriginPickerPresented = true
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.bookHoldingsClient.fetch = { _ in [holding] }
            $0.routePlanningClient.plan = { map, labels, start, stops in
                try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
            }
        }
        store.exhaustivity = .off
        await store.send(.originConfirmed(.init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2))
        #expect(store.state.startsAfterOriginSelected)
        await store.receive(\.shelf.loadMissingHoldings)
        await store.receive(\.shelf.holdingsLoaded)
        await store.receive(\.shelf.resolveLocations)
        await store.receive(\.routeLoaded, timeout: .seconds(10))
        #expect(store.state.navigation != nil)
        #expect(store.state.navigation?.routePlan.start.source == .manual)
        #expect(store.state.navigation?.usesManualOrigin == true)
        let manualStart = store.state.currentStart
        store.state.$location.withLock { $0.apply(.position(position(floor: 4))) }
        await store.send(.locationUpdated)
        #expect(store.state.currentStart == manualStart)
        #expect(store.state.navigation?.routePlan.start == manualStart)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 실패_화면은_문구가_아닌_오류_종류로_분류한다() {
        for error in [IndoorRoutingError.invalidPosition, .unknownFloor, .farFromGraph] {
            #expect(BookRouteFailureView.Kind(failure: .routing(error)) == .outsideLibrary)
        }
        for error in [IndoorRoutingError.invalidDestination, .noRoute] {
            #expect(BookRouteFailureView.Kind(failure: .routing(error)) == .destinationUnavailable)
        }
        #expect(BookRouteFailureView.Kind(failure: nil) == .dataUnavailable)
        #expect(BookRouteFailureView.Kind(failure: .holdingsUnavailable("현재 위치의 층을 확인할 수 없어요."))
                == .dataUnavailable)
    }

    @Test func 안내_완료_후_부모_화면이_닫힐_때까지_실패나_재계산이_노출되지_않는다() async throws {
        var state = try await makeState(position: position())
        let map = try #require(state.shelf?.map.map)
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let start = try #require(RouteStartPolicy().decide(position: position(), isAuthorized: true, map: map, now: now).startPosition)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let plan = try await RoutePlanningLoader().load(on: map, labels: labels, start: start,
            stops: [.init(book: makeBook(1), holdings: [], candidateShelves: [shelf])])
        state.previewPlan = plan
        state.navigation = BookNavigationFeature.State(routePlan: plan)
        state.navigation?.isArrivalPresented = true
        let dismissed = LockIsolated(false)
        let calls = LockIsolated(0)
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.dismiss = .init { dismissed.setValue(true) }
            $0.recentlyFoundBooksClient.record = { _ in }
            $0.routePlanningClient.plan = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                throw IndoorRoutingError.noRoute
            }
        }
        store.exhaustivity = .off
        await store.send(.preparingTimedOut(requestID: store.state.requestID))
        #expect(!store.state.showsRouteFailure)
        await store.send(.navigation(.presented(.finishFromArrival(stopIndex: 0))))
        #expect(store.state.navigation == nil)
        #expect(store.state.returnsToOriginAfterNavigation)
        let requestID = store.state.requestID
        await store.send(.locationUpdated)
        await store.send(.task)
        await store.send(.preparingTimedOut(requestID: requestID))
        #expect(store.state.requestID == requestID)
        #expect(!store.state.showsRouteFailure)
        await store.send(.navigationCoverDismissed)
        #expect(store.state.returnsToOriginAfterNavigation)
        #expect(!store.state.showsRouteFailure)
        await store.finish()
        #expect(dismissed.value)
        #expect(calls.value == 0)
    }
}
