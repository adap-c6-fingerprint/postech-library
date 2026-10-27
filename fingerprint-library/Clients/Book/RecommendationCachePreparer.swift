import Foundation

/// 추천 알고리즘과 독립적으로 결과의 표지를 준비한다. 네트워크 동시 작업은 최대 두 개다.
nonisolated struct RecommendationCachePreparer: Sendable {
    let store: RecommendationCacheStore
    var loadCover: @Sendable (URL) async throws -> Data
    var now: @Sendable () -> Date = { Date() }

    func prepare(_ result: [Book]) async throws -> CachedRecommendations {
        try Task.checkCancellation()
        let preparationID = await store.beginPreparation()
        let books = Array(result.prefix(6))
        let urls = Set(books.compactMap(\.imageURL)).sorted { $0.absoluteString < $1.absoluteString }
        var covers: [URL: Data] = [:]
        var missing: [URL] = []
        for url in urls {
            try Task.checkCancellation()
            if let data = try await store.coverData(for: url) {
                covers[url] = data
            } else {
                missing.append(url)
            }
        }

        try await withThrowingTaskGroup(of: (URL, Data).self) { group in
            var remaining = missing.makeIterator()
            func add(_ url: URL) {
                group.addTask { [loadCover] in
                    let data = try await loadCover(url)
                    try Task.checkCancellation()
                    try RecommendationCacheStore.validateImage(data)
                    return (url, data)
                }
            }
            for _ in 0..<min(missing.count, 2) {
                if let url = remaining.next() { add(url) }
            }
            while let (url, data) = try await group.next() {
                covers[url] = data
                try Task.checkCancellation()
                if let next = remaining.next() { add(next) }
            }
        }

        try Task.checkCancellation()
        return try await store.save(
            books: books, covers: covers, savedAt: now(), preparationID: preparationID
        )
    }
}
