/// 배포된 저장 키는 이름을 바꾸더라도 문자열 값을 유지해야 한다.
nonisolated enum BookStorageKey {
    static let basketItems = "bookBasketItems"
    static let favoriteRecordKeys = "favoriteBookRecordKeys"
    static let recentSearchQueries = "recentSearchQueries"
}
