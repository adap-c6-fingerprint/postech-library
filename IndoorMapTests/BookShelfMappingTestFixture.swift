import Foundation
@testable import fingerprint_library

/// 실제 API 응답과 구분되는 테스트 도서. 지도 연결 키는 기존 C5 가상 서가를 명시적으로 지정한다.
@MainActor
enum BookShelfMappingTestFixture {
    static let books = [
        book(id: "test-book-a", title: "지도 연결 테스트 도서 A"),
        book(id: "test-book-b", title: "지도 연결 테스트 도서 B"),
        book(id: "test-book-c", title: "지도 연결 테스트 도서 C"),
        book(id: "test-book-no-location", title: "위치 없는 테스트 도서")
    ]

    static let shelfKeys: [String: ShelfKey] = [
        "test-book-a": .init(datasetID: "c5-demo", value: "mock-01"),
        "test-book-b": .init(datasetID: "c5-demo", value: "mock-02"),
        "test-book-c": .init(datasetID: "c5-demo", value: "mock-01")
    ]

    static func selections(for books: [Book]) -> [BookShelfSelection] {
        books.map { .init(bookID: $0.id, shelfKey: shelfKeys[$0.id]) }
    }

    private static func book(id: String, title: String) -> Book {
        Book(id: id, isbn: nil, controlNumber: nil, title: title, author: "테스트 작성자",
             publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }
}
