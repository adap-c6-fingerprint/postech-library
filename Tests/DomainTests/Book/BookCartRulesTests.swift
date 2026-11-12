import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookCartRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 0)

    @Test func 같은_책은_한_번만_담는다() {
        var items: [BookCartItem] = []
        #expect(items.add(makeBook(1), at: now) == .added)
        #expect(items.add(makeBook(1), at: now) == .alreadyAdded)
        #expect(items.count == 1)
    }

    @Test func 서른_권을_넘겨_담지_않는다() {
        var items: [BookCartItem] = []
        for number in 0..<BookCartItem.maxStoredCount {
            #expect(items.add(makeBook(number), at: now) == .added)
        }
        #expect(items.add(makeBook(999), at: now) == .limitExceeded)
        #expect(items.count == 30)
    }

    @Test func 같은_책을_모두_빼고_뺀_권수를_돌려준다() {
        var items: [BookCartItem] = []
        items.add(makeBook(1), at: now)
        items.add(makeBook(2), at: now)
        let removed = items.remove(recordKeys: [makeBook(1).recordKey, makeBook(3).recordKey])
        #expect(removed == 1)
        #expect(items.map(\.book.id) == [makeBook(2).id])
    }

    @Test func 예전_파일_표지만_원격_주소로_바꾼다() throws {
        let file = URL(fileURLWithPath: "/tmp/cover.png")
        let remote = try #require(URL(string: "https://example.com/cover.png"))
        var items: [BookCartItem] = []
        items.add(makeBook(1, imageURL: file), at: now)

        items.repairLegacyCover(of: makeBook(1).id, from: remote, to: file)
        #expect(items[0].book.imageURL == file)

        items.repairLegacyCover(of: makeBook(1).id, from: file, to: remote)
        #expect(items[0].book.imageURL == remote)
        #expect(items[0].addedAt == now)
    }

    @Test(arguments: [(0, false), (1, true), (3, true), (4, false)])
    func 한_번에_안내할_수_있는_책은_1권부터_3권이다(count: Int, allowed: Bool) {
        #expect(BookRouteSelection.allows(bookCount: count) == allowed)
    }
}
