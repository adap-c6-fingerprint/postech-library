//
//  RecommendationDatasetClient.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 앱 번들의 RecommendationDataset.json을 한 번만 읽어 재사용한다.
//  1.6MB 파일이므로 메인 스레드가 아닌 actor에서 읽는다.
//

import ComposableArchitecture
import Foundation

nonisolated struct RecommendationDatasetClient: Sendable {
    var load: @Sendable () async throws -> RecommendationDataset
}

nonisolated enum RecommendationDatasetError: Error, Equatable {
    case missingResource
}

extension RecommendationDatasetClient: DependencyKey {
    private static let loader = RecommendationDatasetLoader()

    static let liveValue = Self(load: { try await loader.load() })

    static let testValue = Self(load: { .empty })
}

extension DependencyValues {
    var recommendationDatasetClient: RecommendationDatasetClient {
        get { self[RecommendationDatasetClient.self] }
        set { self[RecommendationDatasetClient.self] = newValue }
    }
}

/// 처음 요청할 때 파일을 읽고, 이후에는 메모리의 결과를 돌려준다.
actor RecommendationDatasetLoader {
    static let resourceName = "RecommendationDataset"

    private let bundle: Bundle
    private var cached: RecommendationDataset?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load() throws -> RecommendationDataset {
        if let cached { return cached }
        guard let url = bundle.url(forResource: Self.resourceName, withExtension: "json") else {
            throw RecommendationDatasetError.missingResource
        }
        let dataset = try RecommendationDatasetDTO.decode(Data(contentsOf: url))
        cached = dataset
        return dataset
    }
}

// MARK: - JSON 형식 (DTO)

/// JSON을 읽기 위한 전용 구조체. 공용 Book은 Codable이 아니므로 이 구조체로 읽은 뒤 Book 초기화 함수로 넘긴다.
/// 앱이 쓰지 않는 필드(holdings, verification 등)는 선언하지 않으면 디코딩 때 무시된다.
nonisolated struct RecommendationDatasetDTO: Decodable, Sendable {
    let books: [Entry]
    let affiliations: [Affiliation]
    let preferences: [Preference]

    nonisolated struct Entry: Decodable, Sendable {
        let recordID: String
        let book: BookDTO
    }

    nonisolated struct BookDTO: Decodable, Sendable {
        let id: String
        let isbn: String?
        let controlNumber: String?
        let title: String
        let author: String
        let publisher: String?
        let publicationYear: String?
        let description: String? // 현재 파일은 전부 null
        let imageURL: String?    // YES24 표지를 찾지 못한 책은 null
        let subLocation: String?
    }

    nonisolated struct Affiliation: Decodable, Sendable {
        let selectionKey: [String]
        let recordIDs: [String]
    }

    nonisolated struct Preference: Decodable, Sendable {
        let name: String
        let recordIDs: [String]
    }

    static func decode(_ data: Data) throws -> RecommendationDataset {
        try JSONDecoder().decode(Self.self, from: data).dataset
    }

    var dataset: RecommendationDataset {
        let books = Dictionary(books.map { ($0.recordID, $0.book.book) }) { first, _ in first }
        let affiliations = affiliations.compactMap { item -> (path: RecommendationDataset.AffiliationPath, recordIDs: [String])? in
            guard let path = RecommendationDataset.AffiliationPath(key: item.selectionKey) else { return nil }
            return (path, item.recordIDs)
        }
        return RecommendationDataset(
            books: books,
            affiliations: affiliations,
            preferences: preferences.map { ($0.name, $0.recordIDs) }
        )
    }
}

extension RecommendationDatasetDTO.BookDTO {
    nonisolated var book: Book {
        Book(
            id: id, isbn: isbn, controlNumber: controlNumber, title: title, author: author,
            publisher: publisher, publicationYear: publicationYear, description: description,
            imageURL: imageURL.flatMap(URL.init(string:)), subLocation: subLocation
        )
    }
}
