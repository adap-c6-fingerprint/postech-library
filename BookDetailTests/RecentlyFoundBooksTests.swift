import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RecentlyFoundBooksTests {
    @Test("길안내한 책을 넘긴 순서대로 맨 앞에 꽂고, 재실행 후에도 복원한다")
    func recordsNewestFirstAndPersists() {
        let suite = "RecentlyFoundBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentlyFoundBooksClient.userDefaults(suiteName: suite)

        client.record([book(0), book(1)])
        client.record([book(2), book(3), book(4)])

        let restored = RecentlyFoundBooksClient.userDefaults(suiteName: suite)
        #expect(restored.load() == [book(2), book(3), book(4), book(0), book(1)])
    }

    @Test("이미 꽂혀 있는 책을 다시 찾으면 중복 없이 맨 앞으로 옮긴다")
    func movesFoundAgainBookToFront() {
        let suite = "RecentlyFoundBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentlyFoundBooksClient.userDefaults(suiteName: suite)
        client.record([book(0), book(1), book(2)])

        let foundAgain = book(1, id: "other-display-id")
        client.record([foundAgain, foundAgain])

        #expect(client.load() == [foundAgain, book(0), book(2)])
    }

    @Test("빈 목록을 기록하면 기존 기록을 바꾸지 않는다")
    func ignoresEmptyRecord() {
        let suite = "RecentlyFoundBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentlyFoundBooksClient.userDefaults(suiteName: suite)
        client.record([book(0)])

        client.record([])

        #expect(client.load() == [book(0)])
    }

    @Test("ISBN이 없는 책도 기록한다 (책등은 대체 막대로 그린다)")
    func recordsBookWithoutISBN() {
        let suite = "RecentlyFoundBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentlyFoundBooksClient.userDefaults(suiteName: suite)
        let noISBN = Book(id: "no-isbn", isbn: nil, controlNumber: "alma-no-isbn", title: "ISBN 없는 책",
                          author: "저자", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)

        client.record([noISBN])

        #expect(client.load() == [noISBN])
    }

    private func book(_ index: Int, id: String? = nil) -> Book {
        Book(id: id ?? "book-\(index)", isbn: "978896626095\(index)", controlNumber: "alma99100095875970328\(index)",
             title: "블렌더 \(index)", author: "권현민", publisher: "출판사", publicationYear: "2023",
             description: nil, imageURL: URL(string: "https://example.com/cover.jpg"))
    }
}
