import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookFavoriteRecordsTests {
    @Test func 같은_책을_다시_찜하면_기록을_바꾼다() {
        var records: [BookFavoriteItem] = []
        records.record(makeBook(1), at: Date(timeIntervalSinceReferenceDate: 1))
        records.record(makeBook(1), at: Date(timeIntervalSinceReferenceDate: 2))
        #expect(records.count == 1)
        #expect(records[0].favoritedAt == Date(timeIntervalSinceReferenceDate: 2))
    }

    @Test func 찜_키에_남은_책만_목록에_보인다() {
        var records: [BookFavoriteItem] = []
        records.record(makeBook(1), at: .distantPast)
        records.record(makeBook(2), at: .distantPast)
        let active = records.active(in: [makeBook(2).recordKey])
        #expect(active.map(\.book.id) == [makeBook(2).id])
    }
}
