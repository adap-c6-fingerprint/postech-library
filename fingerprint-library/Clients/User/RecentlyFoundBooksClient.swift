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
    // 최근에 찾은 책이 앞(책장의 왼쪽)에 온다.
    var record: @Sendable ([Book]) -> Void
    // 한 번에 길안내한 책들을 넘긴 순서대로 맨 앞에 꽂는다. 기존 책은 뒤(오른쪽)로 밀린다.

    private static let storageKey = "recentlyFoundBooks"

    // 테스트에서는 별도 suite를 사용해 앱의 실제 기록과 분리한다. (RecentlyViewedBooksClient와 같은 방식)
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
                // 한 번에 같은 책이 두 번 넘어와도 한 권만 꽂는다.
                let stored = found + read().filter { old in !books.contains(where: { old.matches($0) }) }
                // 이미 꽂혀 있던 책을 다시 찾으면 기존 자리에서 빼고 맨 앞으로 옮긴다.
                let data = try? JSONEncoder().encode(stored)
                defaults().set(data, forKey: storageKey)
            }
        )
    }

    /// Book은 Codable이 아니므로 저장용 구조체로 바꿔 보관한다.
    private nonisolated struct StoredBook: Codable, Sendable {
        let id: String
        let isbn: String?
        // 책등 이미지는 ISBN으로 찾으므로 반드시 함께 저장한다.
        let controlNumber: String?
        let title: String
        // 책등 이미지가 없을 때 세로 제목 막대로 그린다.
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
        // 화면마다 id가 달라도 같은 자료(recordKey)면 같은 책으로 본다. (RecentSearchBooksClient와 같은 기준)
    }
}

extension RecentlyFoundBooksClient: DependencyKey {
    static let liveValue = Self.userDefaults()

    static let testValue = Self(
        load: { [] },
        record: { _ in }
    )
}

extension DependencyValues {
    var recentlyFoundBooksClient: RecentlyFoundBooksClient {
        get { self[RecentlyFoundBooksClient.self] }
        set { self[RecentlyFoundBooksClient.self] = newValue }
    }
}
