import ComposableArchitecture
import Foundation
import Synchronization
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
            $0.date.now = Date(timeIntervalSince1970: 100)
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
            $0.libraryInfoInFlight = [book.id]
        }
        await store.receive(\.libraryInfoFailed) {
            $0.libraryInfo[book.id] = .failed
            $0.libraryInfoInFlight = []
        }
        #expect(store.state.popularBooks == [book])
        await store.send(.loadLibraryInfo) {
            $0.libraryInfoGeneration = 2
            $0.libraryInfo[book.id] = .loading
            $0.libraryInfoInFlight = [book.id]
        }
        await store.receive(\.libraryInfoLoaded) {
            $0.libraryInfo[book.id] = .loaded(.init(holdings: [holding]))
            $0.libraryInfoInFlight = []
            $0.libraryInfoUpdatedAt[book.id] = Date(timeIntervalSince1970: 100)
        }
        await store.finish()
    }

    @Test("자료 번호 누락은 통신하지 않고 이전 목록의 응답을 무시한다")
    func rejectsMissingIDsAndStaleResponses() async {
        let book = book(controlNumber: "invalid")
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 100)
            $0.bookHoldingsClient.fetch = { _ in Issue.record("자료 번호 없이는 통신하지 않습니다"); return [] }
        }
        await store.send(.loadLibraryInfo) {
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
            $0.date.now = Date(timeIntervalSince1970: 100)
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
            $0.libraryInfoInFlight = [book.id]
        }
        var start = started.stream.makeAsyncIterator()
        _ = await start.next()
        await store.send(.libraryInfoCancelled) {
            $0.libraryInfoGeneration = 2
            $0.libraryInfoInFlight = []
        }
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
            $0.date.now = Date(timeIntervalSince1970: 100)
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

    @Test("느린 첫 요청을 기다리지 않고 다음 책을 조회한다")
    func slowRequestDoesNotBlockNextBook() async {
        let books = (0..<6).map { book(index: $0) }
        let firstID = BookHoldingsClient.recordID(for: books[0])!
        let fourthID = BookHoldingsClient.recordID(for: books[3])!
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let started = Mutex<Set<String>>([])
        var initial = HomeFeature.State()
        initial.popularBooks = books
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { id in
                started.withLock { _ = $0.insert(id) }
                if id == firstID { for await _ in gate.stream { break } }
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        // 처음 세 권 중 한 권은 아직 대기 중이어도 네 번째 책의 응답을 받을 수 있다.
        for _ in 0..<3 { await store.receive(\.libraryInfoLoaded) }
        #expect(started.withLock { $0.contains(fourthID) })
        #expect(store.state.libraryInfo[books[0].id] == .loading)
        gate.continuation.finish()
        for _ in 0..<3 { await store.receive(\.libraryInfoLoaded) }
        await store.finish()
        #expect(store.state.libraryInfoInFlight.isEmpty)
        #expect(store.state.libraryInfoPending.isEmpty)
    }

    @Test("전체 목록이 추가돼도 기존 요청을 취소·중복하지 않고 3건 한도를 유지한다")
    func extendsQueueWhenDepartmentBooksArrive() async {
        let books = (0..<6).map { book(index: $0) }
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let calls = Mutex<[String]>([])
        var initial = HomeFeature.State()
        initial.popularBooks = Array(books.prefix(3))
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { id in
                calls.withLock { $0.append(id) }
                for await _ in gate.stream { break }
                try Task.checkCancellation()
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        await store.send(.departmentRecommendationsLoaded(books))
        await store.send(.loadLibraryInfo)
        #expect(store.state.libraryInfoGeneration == 1)
        #expect(store.state.libraryInfoInFlight == Set(books.prefix(3).map(\.id)))
        #expect(store.state.libraryInfoPending == books.suffix(3).map(\.id))
        gate.continuation.finish()
        for _ in 0..<6 { await store.receive(\.libraryInfoLoaded) }
        await store.finish()
        #expect(calls.withLock { $0.count } == 6)
        #expect(calls.withLock { Set($0).count } == 6)
    }

    @Test("재진입 시 최근 성공 결과는 유지하고 실패·미완료 항목만 다시 조회한다")
    func resumesOnlyFailedAndUnfinishedBooks() async {
        let books = (0..<3).map { book(index: $0) }
        let timestamp = Date(timeIntervalSince1970: 100)
        let existingInfo = HomeFeature.LibraryInfoState.loaded(.init(holdings: [holding()]))
        let calls = Mutex<[String]>([])
        var initial = HomeFeature.State()
        initial.popularBooks = books
        initial.libraryInfo = [books[0].id: existingInfo, books[1].id: .failed, books[2].id: .loading]
        initial.libraryInfoUpdatedAt[books[0].id] = timestamp
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.date.now = timestamp.addingTimeInterval(59)
            $0.bookHoldingsClient.fetch = { id in calls.withLock { $0.append(id) }; return [] }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        #expect(store.state.libraryInfo[books[0].id] == existingInfo)
        for _ in 0..<2 { await store.receive(\.libraryInfoLoaded) }
        await store.finish()
        #expect(calls.withLock { Set($0) } == Set(books.suffix(2).compactMap { BookHoldingsClient.recordID(for: $0) }))
        #expect(store.state.libraryInfo[books[0].id] == existingInfo)
    }

    @Test("만료된 성공 정보는 다시 조회한다")
    func reloadsExpiredSuccess() async {
        let book = book()
        let timestamp = Date(timeIntervalSince1970: 100)
        let calls = Mutex(0)
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        initial.libraryInfo[book.id] = .loaded(.init(holdings: [holding()]))
        initial.libraryInfoUpdatedAt[book.id] = timestamp
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.date.now = timestamp.addingTimeInterval(60)
            $0.bookHoldingsClient.fetch = { _ in calls.withLock { $0 += 1 }; return [] }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        await store.receive(\.libraryInfoLoaded)
        await store.finish()
        #expect(calls.withLock { $0 } == 1)
        #expect(store.state.libraryInfo[book.id] == .loaded(.init(holdings: [])))
        #expect(store.state.libraryInfoUpdatedAt[book.id] == timestamp.addingTimeInterval(60))
    }

    @Test("조회 중 같은 목록을 다시 요청해도 진행 중 요청을 중복하지 않는다")
    func doesNotDuplicateInFlightRequests() async {
        let book = book()
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let calls = Mutex(0)
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in
                calls.withLock { $0 += 1 }
                for await _ in gate.stream { break }
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        await store.send(.loadLibraryInfo)
        #expect(store.state.libraryInfoGeneration == 1)
        gate.continuation.finish()
        await store.receive(\.libraryInfoLoaded)
        await store.finish()
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("조회 취소 후 대기열을 비우고 늦은 응답으로 다음 요청을 시작하지 않는다")
    func cancellationClearsQueue() async {
        let books = (0..<6).map { book(index: $0) }
        let started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        let calls = Mutex(0)
        var initial = HomeFeature.State()
        initial.popularBooks = books
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in
                calls.withLock { $0 += 1 }
                started.continuation.yield()
                try await Task.sleep(for: .seconds(60))
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        var iterator = started.stream.makeAsyncIterator()
        for _ in 0..<3 { _ = await iterator.next() }
        await store.send(.libraryInfoCancelled)
        await store.finish()
        await store.send(.libraryInfoLoaded(generation: 1, books[0].id, []))
        await store.send(.libraryInfoFailed(generation: 1, books[1].id))
        #expect(store.state.libraryInfoPending.isEmpty)
        #expect(store.state.libraryInfoInFlight.isEmpty)
        #expect(calls.withLock { $0 } == 3)
    }

    @Test("일시적 오류는 버튼 액션 없이 같은 조회 안에서 복구해 카드에 반영한다")
    func automaticallyRecoversTransientFailure() async {
        let book = book()
        let calls = Mutex(0)
        let service = PrimoBookHoldingsService(relay: .test { request in
            let attempt = calls.withLock { $0 += 1; return $0 }
            if attempt == 1 { throw URLError(.timedOut) }
            let json = #"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]}},"delivery":{"holding":[{"callNumber":"Q1","availabilityStatus":"available"}]}}]}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, sleep: { _ in })
        var initial = HomeFeature.State()
        initial.popularBooks = [book]
        let store = TestStore(initialState: initial) { HomeFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { try await service.fetch(recordID: $0) }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.loadLibraryInfo)
        await store.receive(\.libraryInfoLoaded)
        await store.finish()
        #expect(calls.withLock { $0 } == 2)
        guard case let .loaded(info) = store.state.libraryInfo[book.id] else {
            Issue.record("자동 복구된 결과가 카드에 반영되어야 합니다")
            return
        }
        #expect(info.availability == .available)
    }

    private func book(index: Int = 0, controlNumber: String? = nil) -> Book {
        Book(id: "book-\(index)", isbn: nil,
             controlNumber: controlNumber ?? "primo:alma\(991000958759703286 + index)", title: "도서 \(index)", author: "저자",
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
