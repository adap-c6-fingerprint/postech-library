import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeMapAnnotationsFeatureTests {
        @Test("로컬에 위치가 없는 찜도 검색·소장·HTTP 요청을 만들지 않는다")
        func neverQueriesUnknownFavorites() async {
            let requests = LockIsolated(0)
            let store = Store(initialState: HomeMapAnnotationsFeature.State()) { HomeMapAnnotationsFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { _ in requests.withValue { $0 += 1 }; return [] }
                $0.bookSearchClient.search = { _, _ in requests.withValue { $0 += 1 }; return [] }
                $0.httpClient = HTTPClient(load: { _ in
                    requests.withValue { $0 += 1 }
                    throw URLError(.notConnectedToInternet)
                })
            }
            let keys: Set<[String?]> = [["control", "alma991000000001"], ["metadata", "9780131103627", "책"]]
            await store.send(.task).finish()
            await store.send(.favoritesChanged(keys)).finish()
            store.send(.amenitiesTapped)
            store.send(.localLocationsChanged)
            store.send(.favoritesChanged([]))
            await store.send(.disappeared).finish()
            #expect(store.holdings.isEmpty)
            #expect(requests.value == 0)
        }

        @Test("찜한 책만 로컬 위치를 읽고 취소·편의시설 전환은 다른 책의 위치를 바꾸지 않는다")
        func usesOnlyLocalSnapshots() async {
            let book = BookHoldingTestData.book()
            let key = book.recordKey
            let copy = BookHoldingTestData.holding()
            let store = Store(initialState: HomeMapAnnotationsFeature.State()) { HomeMapAnnotationsFeature() } withDependencies: {
                $0.bookLocationCacheClient.load = { keys in keys.contains(key) ? [key: [copy]] : [:] }
            }
            #expect(!store.showsAmenities)
            store.send(.favoritesChanged([key]))
            #expect(store.holdings == [key: [copy]])
            store.send(.amenitiesTapped)
            #expect(store.showsAmenities)
            #expect(store.holdings == [key: [copy]])
            store.send(.favoritesChanged([]))
            #expect(store.holdings.isEmpty)
        }

        @Test("일반 상세 조회 결과가 로컬에 도착하면 열린 홈의 하트를 갱신한다")
        func observesLocalUpdates() async throws {
            let suite = "local-marker-\(UUID())"
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
            let book = BookHoldingTestData.book()
            let store = Store(initialState: HomeMapAnnotationsFeature.State()) { HomeMapAnnotationsFeature() } withDependencies: {
                $0.bookLocationCacheClient = cache
            }
            store.send(.favoritesChanged([book.recordKey]))
            let task = store.send(.task)
            cache.record(book, [BookHoldingTestData.holding()])
            let deadline = Date().addingTimeInterval(2)
            while store.holdings.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(store.holdings[book.recordKey]?.count == 1)
            await store.send(.disappeared).finish()
            await task.finish()
        }
    }
}
