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
            guard book.imageURL == nil || BookCoverFailure.isUnavailable(error) else { throw error }
            return nil
        }
    }
}
