import Foundation

nonisolated struct RecommendationCachePreparer: Sendable {
    private typealias Cover = RecommendationCacheStore.PreparedCover

    let store: RecommendationCacheStore
    var loadCover: @Sendable (URL) async throws -> Data
    var lookupYes24: @Sendable (String) async throws -> URL?
    var now: @Sendable () -> Date

    init(
        store: RecommendationCacheStore,
        loadCover: @escaping @Sendable (URL) async throws -> Data,
        lookupYes24: @escaping @Sendable (String) async throws -> URL?,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.loadCover = loadCover
        self.lookupYes24 = lookupYes24
        self.now = now
    }

    init(
        store: RecommendationCacheStore,
        loadCover: @escaping @Sendable (URL) async throws -> Data,
        lookupYes24: @escaping @Sendable (String) async throws -> URL?
    ) {
        self.init(store: store, loadCover: loadCover, lookupYes24: lookupYes24, now: { Date() })
    }

    func prepare(_ result: [Book]) async throws -> CachedRecommendations {
        try Task.checkCancellation()
        let preparationID = await store.beginPreparation()
        let candidates = Array(result.prefix(6))
        let prepared = try await withThrowingTaskGroup(of: (Int, Cover?).self) { group in
            var remaining = candidates.indices.makeIterator()
            func add(_ index: Int) {
                let book = candidates[index]
                group.addTask { (index, try await prepareCover(for: book)) }
            }
            for _ in 0..<min(candidates.count, 2) {
                if let index = remaining.next() { add(index) }
            }
            var prepared: [Int: Cover] = [:]
            while let (index, cover) = try await group.next() {
                prepared[index] = cover
                try Task.checkCancellation()
                if let next = remaining.next() { add(next) }
            }
            return prepared
        }

        try Task.checkCancellation()
        var covers: [Book.ID: Cover] = [:]
        var books = candidates
        for (index, cover) in prepared {
            let book = candidates[index]
            covers[book.id] = cover
            if book.imageURL == nil {
                books[index] = Book(
                    id: book.id, isbn: book.isbn, controlNumber: book.controlNumber,
                    title: book.title, author: book.author, publisher: book.publisher,
                    publicationYear: book.publicationYear, description: book.description,
                    imageURL: cover.sourceURL, subLocation: book.subLocation, resourceTypes: book.resourceTypes
                )
            }
        }
        return try await store.save(
            books: books, covers: covers, savedAt: now(), preparationID: preparationID
        )
    }

    func prepareStream(_ candidates: [Book], count: Int) -> AsyncThrowingStream<RecommendationPreparationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let preparationID = await store.beginPreparation()
                    var books: [Book] = []
                    var covers: [Book.ID: Cover] = [:]
                    let sawConnectionProblem = try await forEachCoveredBook(in: candidates, count: count) { book, cover in
                        let file = try await store.writeCover(cover, preparationID: preparationID)
                        books.append(book)
                        covers[book.id] = cover
                        continuation.yield(.book(book, coverFile: file))
                    }
                    if sawConnectionProblem, books.count < count { throw RecommendationPreparationError.offline }
                    guard !books.isEmpty else { throw RecommendationPreparationError.noCoveredBooks }
                    let saved = try await store.save(
                        books: books, covers: covers, savedAt: now(), preparationID: preparationID
                    )
                    continuation.yield(.completed(saved))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    // 표지 확인이 끝난 책부터 바로 내보낸다. 6권이 차면 스냅샷을 저장하고 끝낸다.
    // 연결 문제로 6권을 못 채우면 스냅샷을 저장하지 않고 offline 오류로 끝낸다.

    func verifyCovers(_ candidates: [Book], count: Int) async throws -> [Book] {
        var books: [Book] = []
        let sawConnectionProblem = try await forEachCoveredBook(in: candidates, count: count) { book, _ in
            books.append(book)
        }
        if sawConnectionProblem, books.count < count { throw RecommendationPreparationError.offline }
        return books
    }
    // 다음 묶음용. 화면 뒤에서 준비하므로 한 번에 돌려준다.

    private func forEachCoveredBook(
        in candidates: [Book], count: Int,
        _ body: (Book, Cover) async throws -> Void
    ) async throws -> Bool {
        guard count > 0, !candidates.isEmpty else { return false }
        return try await withThrowingTaskGroup(of: CoverResult.self) { group in
            var remaining = candidates.makeIterator()
            func addNext() {
                guard let book = remaining.next() else { return }
                group.addTask { await coverResult(for: book) }
            }
            for _ in 0..<min(candidates.count, Self.concurrentCoverLoads) { addNext() }

            var found = 0
            var sawConnectionProblem = false
            while let result = try await group.next() {
                try Task.checkCancellation()
                switch result {
                case let .covered(book, cover):
                    try await body(book, cover)
                    found += 1
                    if found == count {
                        group.cancelAll()
                        return sawConnectionProblem
                    }
                case .connectionProblem:
                    sawConnectionProblem = true
                case .skipped:
                    break
                }
                addNext()
            }
            return sawConnectionProblem
        }
    }

    private static let concurrentCoverLoads = 2

    nonisolated private enum CoverResult: Sendable {
        case covered(Book, Cover)
        case connectionProblem
        case skipped
    }

    private func coverResult(for book: Book) async -> CoverResult {
        do {
            guard let cover = try await prepareCover(for: book) else { return .skipped }
            let covered = book.imageURL == nil ? book.replacingImageURL(cover.sourceURL) : book
            return .covered(covered, cover)
        } catch {
            return BookCoverFailure.isConnectionProblem(error) ? .connectionProblem : .skipped
        }
    }
    // 표지가 없거나 서버·이미지 문제로 실패한 책은 건너뛰고 다음 후보를 쓴다.

    private func prepareCover(for book: Book) async throws -> Cover? {
        do {
            return try await BookCoverSource.load(
                url: book.imageURL, isbn13: BookISBN.isbn13(from: book.isbn), lookupYes24: lookupYes24
            ) { url in
                if let data = try await store.coverData(for: url) { return Cover(sourceURL: url, data: data) }
                let data = try await loadCover(url)
                try Task.checkCancellation()
                try RecommendationCacheStore.validateImage(data)
                return Cover(sourceURL: url, data: data)
            }
        } catch {
            try Task.checkCancellation()
            guard !BookCoverFailure.isConnectionProblem(error) else { throw error }
            guard book.imageURL == nil || BookCoverFailure.isUnavailable(error) else { throw error }
            return nil
        }
    }
}

nonisolated enum RecommendationPreparationEvent: Sendable {
    case book(Book, coverFile: URL)
    case completed(CachedRecommendations)
    case offline(fallback: [Book])
}

nonisolated enum RecommendationPreparationError: Error, Equatable {
    case offline
    case noCoveredBooks
}
