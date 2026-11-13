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

    @Test func 못_찾고_안내를_마치면_기록하지_않는다() async throws {
        let recorded = LockIsolated<[[Book]]>([])
        let store = try await Self.makeStore(recorded: recorded)

        await store.send(.deferFromArrival(stopIndex: 0))
        #expect(store.state.exitReason == .cancelled)
        #expect(recorded.value.isEmpty)
    }
}
