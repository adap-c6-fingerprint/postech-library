import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationPositionStabilityTests {
    static let now = Date(timeIntervalSinceReferenceDate: 1_000)
    static let startCoordinate = IndoorMapCoordinate(latitude: 36.0127633, longitude: 129.3251348)

    /// 테스트 대상 Store와, 경로 그래프에 붙은 출발점. 이 테스트들은 경로 위에서 오차만 바뀌는 상황을 본다.
    private static func makeStore() async throws -> (TestStoreOf<BookNavigationFeature>, IndoorMapCoordinate) {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let start = IndoorPosition(coordinate: startCoordinate, floorOrdinal: 2, horizontalAccuracy: 3,
                                   timestamp: now, source: .manual)
        let plan = try await RoutePlanningLoader().load(
            on: map, labels: labels, start: start,
            stops: [RouteCandidateStop(book: makeBook(0), holdings: [], candidateShelves: [shelf])])
        let onRoute = try #require(plan.legs.first).start.routeCoordinate
        var state = BookNavigationFeature.State(routePlan: plan)
        state.isActive = true
        state.authorization = .authorized(precise: true)
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = now
            $0.continuousClock = TestClock()
            $0.analyticsClient = .testValue
        }
        store.exhaustivity = .off
        return (store, onRoute)
    }

    /// 출발점에서 `secondsBeforeNow`초 전에 받은 위치
    private func position(_ coordinate: IndoorMapCoordinate, accuracy: Double, secondsBeforeNow: Double)
        -> IndoorPosition {
        IndoorPosition(coordinate: coordinate, floorOrdinal: 2, horizontalAccuracy: accuracy,
                       timestamp: Self.now.addingTimeInterval(-secondsBeforeNow), source: .sensor)
    }

    @Test func 오차가_10m를_조금_넘어도_안내와_현재_위치를_유지한다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 5, secondsBeforeNow: 8))))
        #expect(store.state.progress != nil)

        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 12, secondsBeforeNow: 7))))
        #expect(store.state.progress != nil)
        #expect(store.state.latestPosition != nil)
        #expect(store.state.statusMessage == nil)
        #expect(store.state.trackingStatus == .degraded)
        await store.skipInFlightEffects()
    }

    @Test func 쓸_수_없는_오차가_3초_넘게_이어질_때만_안내를_멈추고_점은_남긴다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 5, secondsBeforeNow: 8))))
        for seconds in [7.0, 6, 5] {
            await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 20, secondsBeforeNow: seconds))))
            #expect(store.state.statusMessage == nil)
        }
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 20, secondsBeforeNow: 4))))
        #expect(store.state.trackingStatus == .lost)
        #expect(store.state.statusMessage == "위치 오차가 커서 안내를 잠시 멈췄어요.")
        #expect(store.state.latestPosition != nil)

        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 6, secondsBeforeNow: 3))))
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 6, secondsBeforeNow: 2))))
        #expect(store.state.trackingStatus == .tracking)
        #expect(store.state.statusMessage == nil)
        await store.skipInFlightEffects()
    }

    /// 출발점에서 북쪽·동쪽으로 미터 단위만큼 옮긴 좌표
    private func offset(_ coordinate: IndoorMapCoordinate, northMeters: Double, eastMeters: Double)
        -> IndoorMapCoordinate {
        IndoorMapCoordinate(
            latitude: coordinate.latitude + northMeters / 111_195,
            longitude: coordinate.longitude + eastMeters / (111_195 * cos(coordinate.latitude * .pi / 180)))
    }

    @Test func 경로에_매칭되면_지도_점을_경로_위_추정_위치에_붙인다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        let measured = offset(onRoute, northMeters: 1.5, eastMeters: 1.5)
        await store.send(.locationEvent(subscriptionID: 0, .position(position(measured, accuracy: 5, secondsBeforeNow: 1))))
        let progress = try #require(store.state.progress)
        let shown = try #require(store.state.mapPosition)
        #expect(shown.coordinate == progress.coordinate)
        #expect(store.state.latestPosition?.coordinate == measured)
        // 붙인 점이 실제보다 정확해 보이지 않도록 측정 오차·시각을 유지한다.
        #expect(shown.horizontalAccuracy == 5)
        #expect(shown.timestamp == store.state.latestPosition?.timestamp)
        #expect(shown.floorOrdinal == 2)
        await store.skipInFlightEffects()
    }

    @Test func 위치를_잃으면_지도_점을_경로에_붙이지_않고_측정_위치로_둔다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 5, secondsBeforeNow: 8))))
        let measured = offset(onRoute, northMeters: 2, eastMeters: 2)
        for seconds in [7.0, 6, 5, 4] {
            await store.send(.locationEvent(subscriptionID: 0, .position(position(measured, accuracy: 20, secondsBeforeNow: seconds))))
        }
        #expect(store.state.trackingStatus == .lost)
        #expect(store.state.progress != nil)
        #expect(store.state.mapPosition == store.state.latestPosition)
        #expect(store.state.mapPosition?.coordinate == measured)
        await store.skipInFlightEffects()
    }

    @Test func 경로에서_벗어나면_지도_점을_측정_위치로_둔다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 5, secondsBeforeNow: 2))))
        let far = offset(onRoute, northMeters: 7, eastMeters: 7)
        await store.send(.locationEvent(subscriptionID: 0, .position(position(far, accuracy: 5, secondsBeforeNow: 1))))
        #expect(store.state.progress == nil)
        #expect(store.state.mapPosition == store.state.latestPosition)
        #expect(store.state.mapPosition?.coordinate == far)
        await store.skipInFlightEffects()
    }

    @Test func 서가를_찾았다고_하면_그때의_측위_편향을_기억한다() async throws {
        let (store, _) = try await Self.makeStore()
        let destination = try #require(store.state.currentPlan).destination.coordinate
        // 실제로는 서가 앞에 있지만 측위는 북쪽으로 6m 치우친 상황
        let biased = IndoorMapCoordinate(latitude: destination.latitude + 6 / 111_195, longitude: destination.longitude)
        await store.send(.locationEvent(subscriptionID: 0, .position(position(biased, accuracy: 5, secondsBeforeNow: 1))))
        await store.send(.shelfFoundTapped)
        let anchor = try #require(store.state.positionAnchor)
        #expect(anchor.floorOrdinal == 2)
        #expect(abs(anchor.northMeters + 6) < 0.1)
        #expect(RoutingGeometry.distanceMeters(from: anchor.corrected(biased), to: destination) < 0.1)
        await store.skipInFlightEffects()
    }

    @Test func 서가와_너무_먼_곳에서_찾았다고_하면_편향을_기억하지_않는다() async throws {
        let (store, onRoute) = try await Self.makeStore()
        await store.send(.locationEvent(subscriptionID: 0, .position(position(onRoute, accuracy: 5, secondsBeforeNow: 1))))
        await store.send(.shelfFoundTapped)
        #expect(store.state.positionAnchor == nil)
        await store.skipInFlightEffects()
    }
}
