import ComposableArchitecture

nonisolated struct BookSearchCacheClient: Sendable {
    var load: @Sendable (String) -> [Book]?
    var save: @Sendable (String, [Book]) -> Void
    var remove: @Sendable (String) -> Void

    static func inMemory(_ cache: BookSearchResultCache = BookSearchResultCache()) -> Self {
        Self(
            load: { cache.load($0) },
            save: { cache.save($1, for: $0) },
            remove: { cache.remove($0) }
        )
    }
}

extension BookSearchCacheClient: DependencyKey {
    static let liveValue = Self.inMemory()
    static let testValue = Self(load: { _ in nil }, save: { _, _ in }, remove: { _ in })
}

extension DependencyValues {
    var bookSearchCache: BookSearchCacheClient {
        get { self[BookSearchCacheClient.self] }
        set { self[BookSearchCacheClient.self] = newValue }
    }
}
