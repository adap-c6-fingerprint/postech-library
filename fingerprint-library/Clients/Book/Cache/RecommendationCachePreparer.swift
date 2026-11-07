import Foundation

/// 추천 알고리즘과 독립적으로 결과의 표지를 준비한다. 네트워크 동시 작업은 최대 두 개다.
nonisolated struct RecommendationCachePreparer: Sendable {
    private typealias Cover = (url: URL, data: Data)

    let store: RecommendationCacheStore
    var loadCover: @Sendable (URL) async throws -> Data
    var lookupYes24: @Sendable (String) async throws -> URL?
    var now: @Sendable () -> Date = { Date() }

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
        var covers: [URL: Data] = [:]
        let books = candidates.enumerated().map { index, book in
            guard let cover = prepared[index] else { return book }
            covers[cover.url] = cover.data
            return Book(
                id: book.id, isbn: book.isbn, controlNumber: book.controlNumber,
                title: book.title, author: book.author, publisher: book.publisher,
                publicationYear: book.publicationYear, description: book.description,
                imageURL: cover.url, subLocation: book.subLocation, resourceTypes: book.resourceTypes
            )
        }
        let unavailable = Set(books.compactMap(\.imageURL)).subtracting(covers.keys)
        return try await store.save(
            books: books, covers: covers, savedAt: now(),
            unavailableCovers: unavailable, preparationID: preparationID
        )
    }

    private func prepareCover(for book: Book) async throws -> Cover? {
        do {
            return try await BookCoverSource.load(
                url: book.imageURL, isbn13: BookISBN.isbn13(from: book.isbn), lookupYes24: lookupYes24
            ) { url in
                if let data = try await store.coverData(for: url) { return (url, data) }
                let data = try await loadCover(url)
                try Task.checkCancellation()
                try RecommendationCacheStore.validateImage(data)
                return (url, data)
            }
        } catch {
            try Task.checkCancellation()
            guard book.imageURL == nil || BookCoverFailure.isUnavailable(error) else { throw error }
            return nil
        }
    }
}
