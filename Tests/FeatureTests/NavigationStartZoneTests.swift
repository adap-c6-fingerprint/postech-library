import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct NavigationStartZoneTests {
    @Test func 수동_안내는_센서가_다른_위치와_층을_보내도_출발점과_경로를_유지한다() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let manual = IndoorPosition(coordinate: .init(latitude: 36.0127633, longitude: 129.3251348),
            floorOrdinal: 2, horizontalAccuracy: nil, timestamp: now, source: .manual)
        let plan = try await RoutePlanningLoader().load(on: map, labels: labels, start: manual,
            stops: [.init(book: makeBook(1), holdings: [], candidateShelves: [shelf])])
        let state = BookNavigationFeature.State(routePlan: plan, usesManualOrigin: true)
        let clock = TestClock()
        let reroutes = LockIsolated(0)
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = now
            $0.continuousClock = clock
            $0.routePlanningClient.plan = { _, _, _, _ in
                reroutes.withValue { $0 += 1 }
                throw IndoorRoutingError.noRoute
            }
        }
        store.exhaustivity = .off
        await store.send(.sceneActiveChanged(true))
        let subscriptionID = store.state.subscriptionID
        await store.send(.locationEvent(subscriptionID: subscriptionID, .authorization(.authorized(precise: true))))
        for age in [8.0, 1.0] {
            let sensed = IndoorPosition(coordinate: .init(latitude: 36.0128882, longitude: 129.3255185),
                floorOrdinal: 4, horizontalAccuracy: 3, timestamp: now.addingTimeInterval(-age), source: .sensor)
            await store.send(.locationEvent(subscriptionID: subscriptionID, .position(sensed)))
        }
        await clock.advance(by: .seconds(30))
        #expect(store.state.routePlan == plan)
        #expect(store.state.currentFloor?.ordinal == 2)
        #expect(store.state.rawPosition == nil)
        #expect(store.state.offRouteSince == nil)
        #expect(reroutes.value == 0)
        #expect(store.state.startNotice == "직접 지정한 출발 위치에서 안내해요.")
        #expect(store.state.statusMessage == nil)
        await store.send(.recenterTapped)
        #expect(store.state.currentFloor?.ordinal == 2)
        await store.send(.sceneActiveChanged(false))
        await store.send(.sceneActiveChanged(true))
        #expect(store.state.currentFloor?.ordinal == 2)
        #expect(store.state.currentRoute == plan.legs.first)
        await store.send(.disappeared)
        await store.finish()
    }

    @Test func 주출입구_출발은_밖에서_경로를_유지하고_들어오면_층_없이도_이어진다() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let outside = IndoorPosition(coordinate: .init(latitude: 36.0129329, longitude: 129.3256179),
            floorOrdinal: nil, horizontalAccuracy: 5, timestamp: now, source: .sensor)
        let decision = RouteStartPolicy().decide(position: outside, isAuthorized: true, map: map, now: now)
        let start = try #require(decision.startPosition)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let plan = try await RoutePlanningLoader().load(on: map, labels: labels, start: start,
            stops: [.init(book: makeBook(1), holdings: [], candidateShelves: [shelf])])
        var state = BookNavigationFeature.State(routePlan: plan, startsAtEntrance: true)
        #expect(state.confirmedFloorOrdinal == 0)
        state.isActive = true
        state.subscriptionID = 1
        state.authorization = .authorized(precise: true)
        let clock = TestClock()
        let reroutes = LockIsolated(0)
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = now
            $0.continuousClock = clock
            $0.routePlanningClient.plan = { _, _, _, _ in
                reroutes.withValue { $0 += 1 }
                throw IndoorRoutingError.noRoute
            }
        }
        store.exhaustivity = .off
        func position(_ latitude: Double, _ longitude: Double, age: TimeInterval) -> IndoorPosition {
            .init(coordinate: .init(latitude: latitude, longitude: longitude), floorOrdinal: nil,
                  horizontalAccuracy: 5, timestamp: now.addingTimeInterval(-age), source: .sensor)
        }
        await store.send(.locationEvent(subscriptionID: 1,
            .position(position(36.0130858, 129.3259576, age: 2))))
        #expect(store.state.libraryZone == .farOutside)
        #expect(store.state.statusMessage == "도서관에 도착하면 안내를 시작할게요.")
        #expect(store.state.progress == nil)
        #expect(store.state.latestPosition == nil)
        #expect(store.state.entranceApproach == nil)
        #expect(store.state.currentRoute == plan.legs.first)

        await store.send(.locationEvent(subscriptionID: 1,
            .position(position(36.0129329, 129.3256179, age: 1))))
        #expect(store.state.libraryZone == .nearOutside)
        #expect(store.state.statusMessage == "점선을 따라 주출입구로 이동해 주세요.")
        #expect(store.state.offRouteSince == nil)
        #expect(store.state.entranceApproach?.coordinates == [store.state.rawPosition!.coordinate, start.coordinate])
        #expect(store.state.mapPosition == store.state.rawPosition)
        #expect(!store.state.isReroutingCurrentStop)
        #expect(reroutes.value == 0)

        await store.send(.locationEvent(subscriptionID: 1,
            .position(position(36.0128882, 129.3255185, age: 0))))
        #expect(store.state.libraryZone == .inside)
        #expect(store.state.entranceApproach == nil)
        #expect(store.state.effectiveFloorOrdinal == 0)
        #expect(store.state.latestPosition?.floorOrdinal == 0)
        #expect(store.state.statusMessage != "현재 층을 선택해 주세요.")
        #expect(store.state.currentRoute == plan.legs.first)
        await store.send(.disappeared)
        await store.finish()
    }
}
