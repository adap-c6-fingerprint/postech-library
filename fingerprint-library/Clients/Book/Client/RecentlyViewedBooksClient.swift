//
//  RecentlyViewedBooksClient.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 책 상세 화면에 들어간 도서(Q5 '조회')를 최신순으로 저장한다.
//  개인별 추천의 '이후 접속' 규칙이 이 기록으로 연관도서를 찾는다.
//

import ComposableArchitecture
import Foundation

nonisolated struct RecentlyViewedBooksClient: Sendable {
    var load: @Sendable () -> [Book]
    // 최근에 본 책이 앞에 온다.
    var record: @Sendable (Book) -> Void

    static let maxCount = 20
    private static let storageKey = "recentlyViewedBooks"

    // 테스트에서는 별도 suite를 사용해 앱의 실제 기록과 분리한다. (SearchHistoryClient와 같은 방식)
    static func userDefaults(suiteName: String? = nil) -> Self {
        @Sendable func defaults() -> UserDefaults {
            suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        }
        @Sendable func read() -> [StoredBook] {
            guard let data = defaults().data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode([StoredBook].self, from: data)) ?? []
        }
        return Self(
            load: { read().map(\.book) },
            record: { book in
                // 같은 책을 다시 보면 맨 앞으로 옮긴다.
                let stored = [StoredBook(book)] + read().filter { $0.id != book.id }
                let data = try? JSONEncoder().encode(Array(stored.prefix(maxCount)))
                defaults().set(data, forKey: storageKey)
            }
        )
    }

    /// Book은 Codable이 아니므로 저장용 구조체로 바꿔 보관한다.
    private nonisolated struct StoredBook: Codable, Sendable {
        let id: String
        let isbn: String?
        let controlNumber: String?
        let title: String
        let author: String
        let publisher: String?
        let publicationYear: String?
        let imageURL: URL?

        init(_ book: Book) {
            id = book.id
            isbn = book.isbn
            controlNumber = book.controlNumber
            title = book.title
            author = book.author
            publisher = book.publisher
            publicationYear = book.publicationYear
            imageURL = book.imageURL
        }

        var book: Book {
            Book(
                id: id, isbn: isbn, controlNumber: controlNumber, title: title, author: author,
                publisher: publisher, publicationYear: publicationYear, description: nil, imageURL: imageURL
            )
        }
    }
}

extension RecentlyViewedBooksClient: DependencyKey {
    static let liveValue = Self.userDefaults()

    static let testValue = Self(
        load: { [] },
        record: { _ in }
    )
}

extension DependencyValues {
    var recentlyViewedBooksClient: RecentlyViewedBooksClient {
        get { self[RecentlyViewedBooksClient.self] }
        set { self[RecentlyViewedBooksClient.self] = newValue }
    }
}
