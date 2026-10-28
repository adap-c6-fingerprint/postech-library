import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomeLibraryInfoTests {
    @Test("소장 정보를 개별 카드에 반영하고 실패 후 다시 조회한다")
    func loadsAndRetries() async {
        let book = book()
        let holding = holding()
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let attempts = AttemptCounter()
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { recordID in
                #expect(recordID == "alma991000958759703286")
                let count = await attempts.next()
                if count == 1 { throw URLError(.notConnectedToInternet) }
                return [holding]
            }
        }
        await store.send(.loadLibraryInfo) {
            $0.libraryInfoGeneration = 1
            $0.libraryInfo[book.id] = .loading
        }
        await store.receive(\.libraryInfoFailed) { $0.libraryInfo[book.id] = .failed }
        #expect(store.state.popularBooks == [book])
        await store.send(.loadLibraryInfo) {
            $0.libraryInfoGeneration = 2
            $0.libraryInfo[book.id] = .loading
        }
        await store.receive(\.libraryInfoLoaded) {
            $0.libraryInfo[book.id] = .loaded(.init(holdings: [holding]))
        }
        await store.finish()
    }

    @Test("자료 번호 누락은 통신하지 않고 이전 목록의 응답을 무시한다")
    func rejectsMissingIDsAndStaleResponses() async {
        let book = book(controlNumber: "invalid")
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in Issue.record("자료 번호 없이는 통신하지 않습니다"); return [] }
        }
        await store.send(.loadLibraryInfo) {
            $0.libraryInfoGeneration = 1
            $0.libraryInfo[book.id] = .unavailable
        }
        await store.send(.libraryInfoLoaded(generation: 0, book.id, [holding()]))
        await store.send(.libraryInfoFailed(generation: 0, book.id))
        await store.send(.libraryInfoLoaded(generation: 1, "removed-book", [holding()]))
        await store.finish()
    }

    @Test("화면을 떠나면 요청을 취소하고 늦은 응답을 무시한다")
    func cancelsOnLeaving() async {
        let book = book()
        let started = AsyncStream<Void>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); cancelled.continuation.finish() }
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in
                started.continuation.yield(())
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled.continuation.yield(()); throw error }
                return []
            }
        }
        await store.send(.loadLibraryInfo) {
            $0.libraryInfoGeneration = 1
            $0.libraryInfo[book.id] = .loading
        }
        var start = started.stream.makeAsyncIterator()
        _ = await start.next()
        await store.send(.libraryInfoCancelled) { $0.libraryInfoGeneration = 2 }
        await store.finish()
        var cancel = cancelled.stream.makeAsyncIterator()
        #expect(await cancel.next() != nil)
        await store.send(.libraryInfoLoaded(generation: 1, book.id, [holding()]))
    }

    @Test("카드가 여러 개여도 소장 조회는 동시에 3건까지만 실행한다")
    func limitsConcurrentRequests() async {
        let books = (0..<6).map { book(index: $0) }
        let probe = ConcurrencyProbe()
        var initial = HomeFeature.State()
        initial.popularBooks = books
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in await probe.fetch() }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        for _ in 0..<6 { await store.receive(\.libraryInfoLoaded) }
        await store.finish()
        #expect(await probe.maximum == 3)
        #expect(await probe.completed == 6)
        #expect(store.state.libraryInfo.count == 6)
        #expect(store.state.libraryInfo.values.allSatisfy { $0 == .loaded(.init(holdings: [])) })
    }

    private func book(index: Int = 0, controlNumber: String? = "primo:alma991000958759703286") -> Book {
        Book(id: "book-\(index)", isbn: nil, controlNumber: controlNumber, title: "도서 \(index)", author: "저자",
             publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }

    private func holding() -> BookHolding {
        .init(holdingID: "h1", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
              locationCode: "c3b", locationName: "단행본3층", callNumber: "CB113.H4", availability: "available")
    }
}

private actor ConcurrencyProbe {
    var active = 0
    var maximum = 0
    var completed = 0
    func fetch() async -> [BookHolding] {
        active += 1
        maximum = max(maximum, active)
        try? await Task.sleep(for: .milliseconds(20))
        active -= 1
        completed += 1
        return []
    }
}

private actor AttemptCounter {
    var count = 0
    func next() -> Int { count += 1; return count }
}
