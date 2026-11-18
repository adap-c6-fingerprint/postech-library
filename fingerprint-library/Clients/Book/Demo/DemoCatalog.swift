//
//  DemoCatalog.swift
//  fingerprint-library
//
//  오프라인 시연(Demo 빌드)에서 녹화하지 않은 검색·소장 조회를 앱 번들의
//  RecommendationDataset.json(소장처·청구기호 포함) 안에서 대신 처리한다.
//  데이터셋에는 대출 상태가 없으므로 소장 정보의 availability는 비워 둔다(“대출 상태 확인 필요”).
//

import Foundation

nonisolated struct DemoCatalog: Equatable, Sendable {
    nonisolated struct Entry: Equatable, Sendable {
        let recordID: String
        let book: Book
        let holdings: [BookHolding]
        let searchText: String
        let searchWords: Set<String>
    }

    let entries: [Entry]

    init(entries: [(recordID: String, book: Book, holdings: [BookHolding], subjects: [String])]) {
        self.entries = entries.map { item in
            let text = Self.normalize(
                ([item.book.title, item.book.author, item.book.publisher ?? ""] + item.subjects).joined(separator: " ")
            )
            return Entry(
                recordID: item.recordID, book: item.book, holdings: item.holdings,
                searchText: text, searchWords: Set(Self.words(in: text))
            )
        }
    }

    func search(_ request: BookSearchRequest, limit: Int = 20) -> [Book] {
        let terms = Self.words(in: Self.normalize(request.query))
        guard !terms.isEmpty else { return [] }
        return entries
            .filter { entry in terms.allSatisfy { Self.matches($0, in: entry) } }
            .map(\.book)
            .filter { request.category.includes($0) }
            .prefix(limit)
            .map { $0 }
    }

    func holdings(recordID: String) -> [BookHolding]? {
        entries.first { $0.recordID == recordID }?.holdings
    }

    /// 짧은 영문 검색어(예: UI)는 단어 일치로만 찾아 guide·build 같은 부분 일치를 막는다.
    private static func matches(_ term: String, in entry: Entry) -> Bool {
        if term.count <= 3, term.allSatisfy(\.isASCII) {
            return entry.searchWords.contains(term)
        }
        return entry.searchText.contains(term)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func words(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

actor DemoCatalogLoader {
    static let shared = DemoCatalogLoader()

    private nonisolated struct DatasetDTO: Decodable {
        let books: [Entry]

        nonisolated struct Entry: Decodable {
            let recordID: String
            let book: RecommendationDatasetDTO.BookDTO
            let holdings: [BookHolding]?
            let resourceType: String?
            let subjects: [String]?
        }
    }

    private let bundle: Bundle
    private var cached: DemoCatalog?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load() throws -> DemoCatalog {
        if let cached { return cached }
        guard let url = bundle.url(forResource: RecommendationDatasetLoader.resourceName, withExtension: "json") else {
            throw RecommendationDatasetError.missingResource
        }
        let catalog = try Self.decode(Data(contentsOf: url))
        cached = catalog
        return catalog
    }

    static func decode(_ data: Data) throws -> DemoCatalog {
        let dataset = try JSONDecoder().decode(DatasetDTO.self, from: data)
        return DemoCatalog(entries: dataset.books.map { entry in
            var book = entry.book.book
            book.resourceTypes = entry.resourceType.map { [$0] } ?? []
            return (entry.recordID, book, entry.holdings ?? [], entry.subjects ?? [])
        })
    }
}
