import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookShelfMapFeatureTests {
        @Test("1~3권의 실제 청구기호를 서가에 연결하고 포커스한다", arguments: [1, 2, 3])
        func mapsOneShelfPerBook(count: Int) async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let books = (0..<count).map(makeBook)
            var initial = try #require(BookShelfMapFeature.State(books: books))
            initial.map.map = map
            initial.map.shelfLabels = labels
            for (index, book) in books.enumerated() {
                initial.holdings[book.id] = .loaded([BookHoldingTestData.holding(index)])
                initial.resolutions[book.id] = BookHoldingShelfResolver().resolve(
                    [BookHoldingTestData.holding(index)], on: map, labels: labels)
            }
            let third = try #require(map.floors.first { $0.ordinal == 2 })
            let fourth = try #require(map.floors.first { $0.ordinal == 3 })
            let fixtures = Array(["S-3F-616-B", "S-3F-612-B", "S-3F-608-B"].prefix(count))
            let shelves = try fixtures.map { fixture in
                try #require(labels.first { $0.fixtureNumber == fixture })
            }
            let store = TestStore(initialState: initial) { BookShelfMapFeature() }
            await store.send(.focusShelfTapped) {
                $0.map.selectedFloorID = third.id
                $0.map.requestCamera(.features(shelves.map(\.mapElementID)))
            }
            #expect(store.state.shelves.map(\.fixtureNumber) == fixtures)
            #expect(store.state.highlightedFeatureIDs.count == count)
            for (index, book) in books.enumerated() {
                #expect(store.state.shelves(for: book.id).first?.fixtureNumber == fixtures[index])
                var single = BookShelfMapFeature.State(book: book)
                single.map.map = map
                single.map.shelfLabels = labels
                single.holdings[book.id] = initial.holdings[book.id]
                single.resolutions[book.id] = initial.resolutions[book.id]
                #expect(single.shelves(for: book.id) == store.state.shelves(for: book.id))
            }
            let lastBook = try #require(books.last)
            let lastShelf = try #require(shelves.last)
            await store.send(.bookShelfTapped(lastBook.id)) {
                $0.map.requestCamera(.features([lastShelf.mapElementID]))
            }
            await store.send(.bookShelfTapped("unknown"))
            let camera = store.state.map.cameraRequest
            await store.send(.map(.floorSelected(fourth.id))) { $0.map.selectedFloorID = fourth.id }
            #expect(store.state.map.cameraRequest == camera)
            await store.send(.focusShelfTapped) {
                $0.map.selectedFloorID = third.id
                $0.map.requestCamera(.features(shelves.map(\.mapElementID)))
            }
            await store.finish()
        }

        @Test("서가 자료 로딩 후에 포커스하고 이탈·재시도 이전 응답은 무시한다")
        func focusesAfterLabelsLoad() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
            var initial = BookShelfMapFeature.State(book: book)
            initial.map.map = map
            initial.holdings[book.id] = .loaded([BookHoldingTestData.holding()])
            initial.map.isLoadingShelfLabels = true
            initial.map.shelfLabelRequestID = 2
            let store = TestStore(initialState: initial) { BookShelfMapFeature() }
            await store.send(.map(.shelfLabelsLoaded(requestID: 1, labels)))
            await store.send(.map(.shelfLabelsLoaded(requestID: 2, labels))) {
                $0.map.isLoadingShelfLabels = false
                $0.map.shelfLabels = labels
            }
            await store.receive(.resolveLocations) {
                $0.resolutions[book.id] = BookHoldingShelfResolver().resolve(
                    [BookHoldingTestData.holding()], on: map, labels: labels)
                $0.map.selectedFloorID = shelf.floorID
                $0.map.requestCamera(.features([shelf.mapElementID]))
            }
            await store.send(.map(.disappeared))
            let camera = store.state.map.cameraRequest
            await store.send(.map(.shelfLabelsLoaded(requestID: 2, labels)))
            #expect(store.state.map.cameraRequest == camera)
            await store.finish()
        }

        @Test("길안내 화면을 열고 dismiss해도 검색 결과와 바구니를 유지한다")
        func preservesSearchAfterDismissal() async {
            var initial = BookSearchFeature.State()
            initial.query = "테스트 검색"
            initial.books = [book]
            initial.hasSearched = true
            initial.basketBooks = [book]
            let store = TestStore(initialState: initial) { BookSearchFeature() }
            await store.send(.directionsButtonTapped(book)) { $0.shelfMap = .init(book: book) }
            #expect(store.state.shelfMap?.books == [book])
            await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
            #expect(store.state == initial)
            await store.finish()
        }

        @Test("서가 자료 재시도 후 소장 청구기호에 해당하는 서가를 강조한다")
        func retriesLabelsForHolding() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let third = try #require(map.floors.first { $0.ordinal == 2 })
            let fourth = try #require(map.floors.first { $0.ordinal == 3 })
            let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
            var initial = BookShelfMapFeature.State(book: book)
            initial.map.map = map
            initial.map.selectedFloorID = third.id
            initial.holdings[book.id] = .loaded([BookHoldingTestData.holding()])
            let store = TestStore(initialState: initial) { BookShelfMapFeature() } withDependencies: {
                $0.indoorShelfLabelClient = .init(
                    supports: { _ in true },
                    load: { _ in throw ShelfLabelLoadError.missingResource }
                )
            }

            await store.send(.map(.retryShelfLabelsTapped)) {
                $0.map.isLoadingShelfLabels = true
                $0.map.shelfLabelRequestID = 1
            }
            await store.receive(\.map.shelfLabelsFailed) {
                $0.map.isLoadingShelfLabels = false
                $0.map.shelfLabelError = ShelfLabelLoadError.missingResource.localizedDescription
            }
            #expect(store.state.map.map == map)
            #expect(store.state.highlightedFeatureIDs.isEmpty)

            let resume = AsyncStream<Void>.makeStream()
            defer { resume.continuation.finish() }
            store.dependencies.indoorShelfLabelClient.load = { _ in
                var iterator = resume.stream.makeAsyncIterator()
                _ = await iterator.next()
                return labels
            }
            await store.send(.map(.retryShelfLabelsTapped)) {
                $0.map.isLoadingShelfLabels = true
                $0.map.shelfLabelError = nil
                $0.map.shelfLabelRequestID = 2
            }
            await store.send(.map(.floorSelected(fourth.id))) {
                $0.map.selectedFloorID = fourth.id
            }
            resume.continuation.yield(())
            await store.receive(\.map.shelfLabelsLoaded) {
                $0.map.isLoadingShelfLabels = false
                $0.map.shelfLabels = labels
            }
            await store.receive(.resolveLocations) {
                $0.resolutions[book.id] = BookHoldingShelfResolver().resolve(
                    [BookHoldingTestData.holding()], on: map, labels: labels)
                $0.map.selectedFloorID = third.id
                $0.map.requestCamera(.features([shelf.mapElementID]))
            }
            #expect(store.state.highlightedFeatureIDs == [shelf.mapElementID])
            #expect(store.state.map.selectedFloorID == third.id)
            await store.finish()
        }

        @Test("바구니에서 고른 1~3권만 보관 순서대로 길안내에 전달한다", arguments: [1, 2, 3])
        func opensSelectedBasketBooks(count: Int) async {
            let basket = (0..<4).map(makeBook)
            let selected = Array(basket.suffix(count))
            var initial = BookSearchFeature.State()
            initial.basketBooks = basket
            initial.query = "검색 유지"
            let store = TestStore(initialState: initial) { BookSearchFeature() }
            await store.send(.basketDirectionsButtonTapped(Set(selected.map(\.id)))) {
                $0.shelfMap = .init(books: selected)
            }
            #expect(store.state.shelfMap?.books == selected)
            #expect(store.state.basketBooks.count == 4)
            await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
            #expect(store.state == initial)
            await store.finish()
        }

        @Test("빈 선택과 4권 이상은 길안내에 전달하지 않는다", arguments: [0, 4])
        func rejectsInvalidBookCount(count: Int) async {
            let books = (0..<4).map(makeBook)
            let selection = Array(books.prefix(count))
            #expect(BookShelfMapFeature.State(books: selection) == nil)
            var initial = BookSearchFeature.State()
            initial.basketBooks = books
            let store = TestStore(initialState: initial) { BookSearchFeature() }
            await store.send(.basketDirectionsButtonTapped(Set(selection.map(\.id))))
            #expect(store.state == initial)
            await store.finish()
        }

        @Test("바구니에 없는 책이 섞이면 일부 책만 전달하지 않는다")
        func rejectsUnknownBasketBook() async {
            var initial = BookSearchFeature.State()
            initial.basketBooks = [book]
            let store = TestStore(initialState: initial) { BookSearchFeature() }
            await store.send(.basketDirectionsButtonTapped([book.id, "unknown"]))
            #expect(store.state == initial)
            await store.finish()
        }

        @Test("지도 로딩 중 dismiss하면 요청을 취소하고 검색·바구니를 보존한다")
        func dismissesWhileLoadingMap() async {
            let started = AsyncStream<Void>.makeStream()
            let cancelled = AsyncStream<Void>.makeStream()
            defer {
                started.continuation.finish()
                cancelled.continuation.finish()
            }
            var initial = BookSearchFeature.State()
            initial.query = "로딩 중 뒤로가기"
            initial.books = [book]
            initial.basketBooks = [book]
            initial.hasSearched = true
            let store = TestStore(initialState: initial) { BookSearchFeature() } withDependencies: {
                $0.indoorMapClient.load = {
                    started.continuation.yield(())
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        if Task.isCancelled { cancelled.continuation.yield(()) }
                        throw error
                    }
                    throw IndoorMapLoadError.missingResource("취소되지 않은 요청")
                }
            }
            await store.send(.directionsButtonTapped(book)) { $0.shelfMap = .init(book: book) }
            await store.send(.shelfMap(.presented(.task))) {
                $0.shelfMap?.holdings[book.id] = .failed(BookHoldingsError.invalidRecordID.localizedDescription)
            }
            await store.receive(\.shelfMap.presented.map.retryTapped) {
                $0.shelfMap?.map.isLoading = true
            }
            var startedIterator = started.stream.makeAsyncIterator()
            _ = await startedIterator.next()
            await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
            await store.finish()
            var cancelledIterator = cancelled.stream.makeAsyncIterator()
            #expect(await cancelledIterator.next() != nil)
            #expect(store.state == initial)
        }

        private var book: Book {
            .init(id: "test-book", isbn: nil, controlNumber: nil, title: "임시 서가 안내 테스트",
                  author: "테스트", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        }

        private func makeBook(_ index: Int) -> Book {
            BookHoldingTestData.book(index)
        }
    }
}
