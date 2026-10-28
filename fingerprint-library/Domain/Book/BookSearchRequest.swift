import Foundation

nonisolated enum BookSearchCategory: String, CaseIterable, Hashable, Sendable {
    case all = "전체"
    case monograph = "단행본"
    case journal = "학술지"
}

/// 검색 요청과 캐시가 같은 검색어·자료 유형을 사용하도록 묶는다.
nonisolated struct BookSearchRequest: Hashable, Sendable {
    let query: String
    let category: BookSearchCategory

    init(query: String, category: BookSearchCategory) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
    }
}
