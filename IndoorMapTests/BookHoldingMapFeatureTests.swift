import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookHoldingMapFeatureTests {
        @Test("이미 불러온 지도로 재진입해도 실제 서가 연결을 복구한다")
        func restoresMappingsOnReentry() async throws {
            let book = BookHoldingTestData.book()
            let holding = BookHoldingTestData.holding()
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
            var initial = BookShelfMapFeature.State(book: book)
            initial.map.map = map
            initial.map.shelfLabels = labels
            initial.holdings[book.id] = .loaded([holding])
            let store = TestStore(initialState: initial) { BookShelfMapFeature() }
            await store.send(.task)
            await store.receive(.map(.retryTapped))
            await store.receive(.resolveLocations) {
                $0.resolutions[book.id] = BookHoldingShelfResolver().resolve([holding], on: map, labels: labels)
                $0.map.selectedFloorID = shelf.floorID
                $0.map.requestCamera(.features([shelf.mapElementID]))
            }
            await store.finish()
        }

        @Test("지도 자료가 먼저 도착해도 소장 정보가 도착하면 실제 서가에 포커스한다")
        func loadsHoldingsThenFocuses() async throws {
            let book = BookHoldingTestData.book()
            let holding = BookHoldingTestData.holding()
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
            var initial = BookShelfMapFeature.State(book: book)
            initial.map.map = map
            initial.map.shelfLabels = labels
            let store = TestStore(initialState: initial) { BookShelfMapFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { recordID in
                    #expect(recordID == "alma991000958759703280")
                    return [holding]
                }
            }
            await store.send(.retryHoldingsTapped(book.id)) {
                $0.holdings[book.id] = .loading
                $0.holdingRequestIDs[book.id] = 1
            }
            await store.receive(.holdingsLoaded(book.id, requestID: 1, [holding])) {
                $0.holdings[book.id] = .loaded([holding])
            }
            await store.receive(.resolveLocations) {
                $0.resolutions[book.id] = BookHoldingShelfResolver().resolve([holding], on: map, labels: labels)
                $0.map.selectedFloorID = shelf.floorID
                $0.map.requestCamera(.features([shelf.mapElementID]))
            }
            #expect(store.state.highlightedFeatureIDs == [shelf.mapElementID])
            await store.finish()
        }

        @Test("이전 요청 응답을 무시하고 실패한 소장 조회를 다시 시도한다")
        func retriesAndRejectsStaleResults() async throws {
            let book = BookHoldingTestData.book()
            let holding = BookHoldingTestData.holding()
            var initial = BookShelfMapFeature.State(book: book)
            initial.holdings[book.id] = .loading
            initial.holdingRequestIDs[book.id] = 2
            let store = TestStore(initialState: initial) { BookShelfMapFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { _ in [holding] }
            }
            await store.send(.holdingsLoaded(book.id, requestID: 1, [holding]))
            await store.send(.holdingsFailed(book.id, requestID: 1, "이전 오류"))
            await store.send(.holdingsFailed(book.id, requestID: 2, "조회 실패")) {
                $0.holdings[book.id] = .failed("조회 실패")
            }
            await store.send(.retryHoldingsTapped(book.id)) {
                $0.holdings[book.id] = .loading
                $0.holdingRequestIDs[book.id] = 3
            }
            await store.receive(.holdingsLoaded(book.id, requestID: 3, [holding])) {
                $0.holdings[book.id] = .loaded([holding])
            }
            await store.receive(.resolveLocations)
            await store.finish()
        }

        @Test("같은 서가는 중복 강조하지 않고 다른 층 후보 버튼은 해당 층으로 이동한다")
        func focusesMultipleFloorsAndSharedShelf() async throws {
            let books = [BookHoldingTestData.book(), BookHoldingTestData.book(1)]
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let third = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
            let fourth = try #require(labels.first { $0.fixtureNumber == "S-4F-706-A" })
            let copies = [BookHoldingTestData.holding(), BookHoldingTestData.holding(code: "c4b")]
            var initial = try #require(BookShelfMapFeature.State(books: books))
            initial.map.map = map
            initial.map.shelfLabels = labels
            initial.holdings[books[0].id] = .loaded(copies)
            initial.holdings[books[1].id] = .loaded([copies[0]])
            let store = TestStore(initialState: initial) { BookShelfMapFeature() }
            await store.send(.resolveLocations) {
                $0.resolutions[books[0].id] = BookHoldingShelfResolver().resolve(copies, on: map, labels: labels)
                $0.resolutions[books[1].id] = BookHoldingShelfResolver().resolve([copies[0]], on: map, labels: labels)
                $0.map.selectedFloorID = third.floorID
                $0.map.requestCamera(.features([third.mapElementID]))
            }
            #expect(store.state.shelves.count == 2)
            #expect(store.state.shelves(for: books[0].id).count == 2)
            await store.send(.candidateTapped(books[0].id, fixtureNumber: fourth.fixtureNumber)) {
                $0.map.selectedFloorID = fourth.floorID
                $0.map.requestCamera(.features([fourth.mapElementID]))
            }
            await store.send(.focusShelfTapped) { $0.map.requestCamera(.features([fourth.mapElementID])) }
            await store.send(.candidateTapped(books[1].id, fixtureNumber: fourth.fixtureNumber))
            await store.finish()
        }

        @Test("소장 정보 로딩 중 닫으면 네트워크 작업을 취소하고 검색 상태를 보존한다")
        func cancelsHoldingsOnDismissal() async throws {
            let book = BookHoldingTestData.book()
            let started = AsyncStream<Void>.makeStream()
            let cancelled = AsyncStream<Void>.makeStream()
            defer { started.continuation.finish(); cancelled.continuation.finish() }
            var initial = BookSearchFeature.State()
            initial.query = "검색 유지"
            initial.books = [book]
            initial.basketBooks = [book]
            let store = TestStore(initialState: initial) { BookSearchFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { _ in
                    started.continuation.yield(())
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { cancelled.continuation.yield(()); throw error }
                    return []
                }
            }
            await store.send(.directionsButtonTapped(book)) { $0.shelfMap = .init(book: book) }
            await store.send(.shelfMap(.presented(.retryHoldingsTapped(book.id)))) {
                $0.shelfMap?.holdings[book.id] = .loading
                $0.shelfMap?.holdingRequestIDs[book.id] = 1
            }
            var start = started.stream.makeAsyncIterator()
            _ = await start.next()
            await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
            await store.finish()
            var cancel = cancelled.stream.makeAsyncIterator()
            #expect(await cancel.next() != nil)
            #expect(store.state == initial)
        }

        @Test("상세 화면에서도 같은 위치 지도로 진입하고 뒤로가면 상세 상태를 보존한다")
        func opensFromBookDetail() async {
            let book = BookHoldingTestData.book()
            var initial = BookDetailFeature.State(book: book)
            initial.hasLoaded = true
            let store = TestStore(initialState: initial) { BookDetailFeature() }
            await store.send(.directionsButtonTapped) { $0.shelfMap = .init(book: book) }
            await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
            #expect(store.state == initial)
            await store.finish()
        }
    }
}
