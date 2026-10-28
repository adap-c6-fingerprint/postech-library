import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookShelfResolverTests {
    private func c5Directory() async throws -> ShelfDirectory {
        let map = try await BundledIndoorMapLoader().loadC5()
        return try await BundledIndoorNavigationLoader().loadC5(on: map).shelves
    }

    @Test("테스트 책이 C5의 지정 서가·층·도착 노드에 연결된다")
    func resolvesExplicitDestinations() async throws {
        let directory = try await c5Directory()
        let books = Array(BookShelfMappingTestFixture.books.prefix(3))
        let mapping = BookShelfResolver().resolve(BookShelfMappingTestFixture.selections(for: books), in: directory)
        #expect(mapping.entries.map(\.bookID) == books.map(\.id))
        let expectedKeys = ["mock-01", "mock-02", "mock-01"]
        for (entry, key) in zip(mapping.entries, expectedKeys) {
            let expected = try directory.destination(for: .init(datasetID: "c5-demo", value: key))
            #expect(entry.outcome == .resolved(expected))
        }
        #expect(mapping.unresolved.isEmpty)
        #expect(directory.destinations[0].floorID != directory.destinations[1].floorID)
    }

    @Test("같은 서가의 책을 한 방문지로 묶어도 선택한 책과 순서가 보존된다")
    func groupsWithoutDroppingBooks() async throws {
        let directory = try await c5Directory()
        let books = Array(BookShelfMappingTestFixture.books.prefix(3))
        let mapping = BookShelfResolver().resolve(BookShelfMappingTestFixture.selections(for: books), in: directory)
        let groups = try mapping.groupedDestinations()
        #expect(groups.map { $0.destination.key.value } == ["mock-01", "mock-02"])
        #expect(groups.map(\.bookIDs) == [["test-book-a", "test-book-c"], ["test-book-b"]])
        #expect(groups.flatMap(\.bookIDs).count == books.count)
        // 메타데이터는 기존 Book 복사본에서 식별자로 찾으며 공유 Book 계약을 추가하지 않는다.
        let metadata = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        #expect(groups.flatMap(\.bookIDs).compactMap { metadata[$0] }.count == books.count)
    }

    @Test("위치 없는 책의 실패를 보존하고 일부만 연결한 방문지는 반환하지 않는다")
    func reportsMissingLocationWithoutPartialSuccess() async throws {
        let directory = try await c5Directory()
        let books = BookShelfMappingTestFixture.books
        let mapping = BookShelfResolver().resolve(BookShelfMappingTestFixture.selections(for: books), in: directory)
        #expect(mapping.entries.map(\.bookID) == books.map(\.id))
        #expect(mapping.unresolved == [.init(bookID: "test-book-no-location", outcome: .unresolved(.missingLocation))])
        #expect(throws: BookShelfMapping.GroupingError.unresolvedBooks(["test-book-no-location"])) {
            try mapping.groupedDestinations()
        }
    }

    @Test("같은 서가 문자열도 데이터셋이 다르면 연결하지 않는다")
    func rejectsDifferentDataset() async throws {
        let directory = try await c5Directory()
        let key = ShelfKey(datasetID: "postech-library", value: "mock-01")
        let mapping = BookShelfResolver().resolve([.init(bookID: "book", shelfKey: key)], in: directory)
        #expect(mapping.entries == [.init(bookID: "book", outcome: .unresolved(.differentDataset(key)))])
    }

    @Test("매핑되지 않은 서가 키를 임의의 가까운 서가로 대체하지 않는다")
    func rejectsUnknownShelf() async throws {
        let directory = try await c5Directory()
        let key = ShelfKey(datasetID: directory.datasetID, value: "unknown-shelf")
        let mapping = BookShelfResolver().resolve([.init(bookID: "book", shelfKey: key)], in: directory)
        #expect(mapping.entries == [.init(bookID: "book", outcome: .unresolved(.unmappedShelf(key)))])
    }

    @Test("빈 선택은 정상 방문지 목록으로 만들지 않는다")
    func rejectsEmptySelection() async throws {
        let mapping = BookShelfResolver().resolve([], in: try await c5Directory())
        #expect(mapping.entries.isEmpty)
        #expect(throws: BookShelfMapping.GroupingError.emptySelection) { try mapping.groupedDestinations() }
    }

    @Test("공백 책 식별자는 입력 값을 보존하며 실패로 처리한다")
    func rejectsEmptyBookID() async throws {
        let directory = try await c5Directory()
        let mapping = BookShelfResolver().resolve([.init(bookID: "  ", shelfKey: directory.destinations[0].key)], in: directory)
        #expect(mapping.entries == [.init(bookID: "  ", outcome: .unresolved(.invalidBookID))])
    }
}
