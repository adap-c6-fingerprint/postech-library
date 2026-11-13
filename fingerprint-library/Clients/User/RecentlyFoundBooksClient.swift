//
//  RecentlyFoundBooksClient.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  책바구니에서 '안내 시작하기'로 길안내를 시작한 책을 최신순으로 저장한다.
//  마이페이지의 최근 찾은 책 책장(RecentlyFoundBookShelf)이 이 기록으로 책등을 그린다.
//

import ComposableArchitecture
import Foundation

nonisolated struct RecentlyFoundBooksClient: Sendable {
    var load: @Sendable () -> [Book]
    var record: @Sendable ([Book]) -> Void

    private static let storageKey = "recentlyFoundBooks"

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
            record: { books in
                guard !books.isEmpty else { return }
                var found: [StoredBook] = []
                for book in books where !found.contains(where: { $0.matches(book) }) {
                    found.append(StoredBook(book))
                }
                let stored = found + read().filter { old in !books.contains(where: { old.matches($0) }) }
                let data = try? JSONEncoder().encode(stored)
                defaults().set(data, forKey: storageKey)
            }
        )
    }

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

        func matches(_ other: Book) -> Bool {
            id == other.id || book.recordKey == other.recordKey
        }
    }
}

extension RecentlyFoundBooksClient: DependencyKey {
    static let liveValue = Self.userDefaults()

    static let testValue = Self(
        load: { [] },
        record: { _ in }
    )
}

nonisolated extension DependencyValues {
    var recentlyFoundBooksClient: RecentlyFoundBooksClient {
        get { self[RecentlyFoundBooksClient.self] }
        set { self[RecentlyFoundBooksClient.self] = newValue }
    }
}
