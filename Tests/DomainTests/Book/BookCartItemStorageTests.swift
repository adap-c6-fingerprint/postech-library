import Foundation
import Testing
@testable import fingerprint_library

/// 책바구니 저장 형식이 이전 BookCartClient가 쓰던 JSON과 같아야 기존 사용자의 책바구니가 유지된다.
@MainActor
struct BookCartItemStorageTests {
    @Test func 이전_저장_JSON을_그대로_읽는다() throws {
        let json = """
        [{"id":"primo:1","controlNumber":"primo:1","title":"책 1","author":"저자",
          "imageURL":"https://example.com/1.png","addedAt":12345.5}]
        """
        let items = try JSONDecoder().decode([BookCartItem].self, from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].book.id == "primo:1")
        #expect(items[0].book.isbn == nil)
        #expect(items[0].book.imageURL == URL(string: "https://example.com/1.png"))
        #expect(items[0].addedAt == Date(timeIntervalSinceReferenceDate: 12345.5))
    }

    @Test func 저장하고_다시_읽으면_같은_값이다() throws {
        var items: [BookCartItem] = []
        items.add(makeBook(7), at: Date(timeIntervalSinceReferenceDate: 99))
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([BookCartItem].self, from: data)
        #expect(decoded == items)
    }
}
