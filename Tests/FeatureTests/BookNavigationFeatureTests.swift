import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationFeatureTests {
    private static func makePlan() async throws -> RoutePlan {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let thirdFloor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelves = try ["343", "320"].map { number in
            try #require(labels.first {
                $0.floorID == thirdFloor.id && $0.realNumber == number && $0.side == .a
            })
        }
        let start = IndoorPosition(
            coordinate: .init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2,
            horizontalAccuracy: 3, timestamp: Date(), source: .manual
        )
        let stops = shelves.enumerated().map { index, shelf in
            RouteCandidateStop(book: makeBook(index), holdings: [], candidateShelves: [shelf])
        }
        return try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
    }

    private static func makeStore(
        recorded: LockIsolated<[[Book]]>
    ) async throws -> TestStoreOf<BookNavigationFeature> {
        var state = BookNavigationFeature.State(routePlan: try await makePlan())
        state.isArrivalPresented = true
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSinceReferenceDate: 0)
            $0.recentlyFoundBooksClient = .init(
                load: { [] },
                record: { books in recorded.withValue { $0.append(books) } }
            )
        }
        store.exhaustivity = .off
        return store
    }

    @Test func 찾았어요를_누른_책만_최근_찾은_책으로_기록한다() async throws {
        let recorded = LockIsolated<[[Book]]>([])
        let store = try await Self.makeStore(recorded: recorded)
        let books = store.state.routePlan.stops.map(\.book)

        await store.send(.continueFromArrival(stopIndex: 0))
        #expect(recorded.value == [[books[0]]])

        await store.send(.shelfFoundTapped)
        await store.send(.arrivalPresentationChanged(true))
        await store.send(.finishFromArrival(stopIndex: 1))
        #expect(recorded.value == [[books[0]], [books[1]]])
    }

    @Test func 층_이동을_확인하면_센서가_출발_층을_보고해도_도착_층에_현재_위치를_표시한다() async throws {
        let base = try await Self.makePlan()
        let floorOrdinals = Set(base.map.floors.map(\.ordinal))
        let nodes = Dictionary(uniqueKeysWithValues: base.graph.nodes.map { ($0.id, $0) })
        let elevatorStart = try #require(base.graph.edges.lazy
            .filter { $0.category == .elevator }
            .compactMap { edge -> RouteNode? in
                guard let from = nodes[edge.fromNodeID], let to = nodes[edge.toNodeID] else { return nil }
                let pair = [from, to]
                return pair.first { $0.level != 2 && floorOrdinals.contains($0.level) && pair.contains { $0.level == 2 } }
            }
            .first)
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let start = IndoorPosition(coordinate: elevatorStart.coordinate, floorOrdinal: elevatorStart.level,
            horizontalAccuracy: 3, timestamp: now, source: .manual)
        let stop = RouteCandidateStop(book: base.stops[0].book, holdings: [], candidateShelves: [base.stops[0].shelf])
        let plan = try await RoutePlanningLoader().load(on: base.map, labels: base.shelfLabels, start: start, stops: [stop])

        var state = BookNavigationFeature.State(routePlan: plan)
        state.isActive = true
        state.authorization = .authorized(precise: true)
        let clock = TestClock()
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = now
            $0.continuousClock = clock
            $0.analyticsClient = .testValue
        }
        store.exhaustivity = .off

        let transition = try #require(store.state.nextFloorTransition)
        #expect(transition.from.level == elevatorStart.level)
        let lagging = IndoorPosition(coordinate: elevatorStart.coordinate, floorOrdinal: transition.from.level,
            horizontalAccuracy: 3, timestamp: now, source: .sensor)
        await store.send(.locationEvent(subscriptionID: 0, .position(lagging)))

        await store.send(.floorTransitionTapped(stopIndex: 0, stepIndex: transition.id))
        #expect(store.state.currentFloor?.ordinal == transition.to.level)
        #expect(store.state.latestPosition?.floorOrdinal == transition.to.level)
        #expect(store.state.showsNativeUserLocation)

        let laterLagging = IndoorPosition(coordinate: elevatorStart.coordinate, floorOrdinal: transition.from.level,
            horizontalAccuracy: 3, timestamp: now.addingTimeInterval(0.5), source: .sensor)
        await store.send(.locationEvent(subscriptionID: 0, .position(laterLagging)))
        #expect(store.state.currentFloor?.ordinal == transition.to.level)
        #expect(store.state.latestPosition?.floorOrdinal == transition.to.level)
        await store.skipInFlightEffects()
    }

    @Test func 못_찾고_안내를_마치면_기록하지_않는다() async throws {
        let recorded = LockIsolated<[[Book]]>([])
        let store = try await Self.makeStore(recorded: recorded)

        await store.send(.deferFromArrival(stopIndex: 0))
        #expect(store.state.exitReason == .cancelled)
        #expect(recorded.value.isEmpty)
    }
}
