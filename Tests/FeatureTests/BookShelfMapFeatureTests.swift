import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookShelfMapFeatureTests {
    @Test func 미리보는_책마다_상세_상태를_한_번씩_둔다() throws {
        let books = [makeBook(1), makeBook(2)]
        try withDependencies { $0.uuid = .incrementing } operation: {
            let state = try #require(BookShelfMapFeature.State(previewing: books))
            #expect(state.details.ids.elements == books.map(\.id))
            #expect(BookShelfMapFeature.State(book: makeBook(3)).details.ids.elements == [makeBook(3).id])
        }
    }

    @Test func 미리보기의_찜_버튼은_합성한_상세_reducer로_공유_찜을_바꾼다() async throws {
        let book = makeBook(1)
        let state = try withDependencies { $0.uuid = .incrementing } operation: {
            try #require(BookShelfMapFeature.State(previewing: [book, makeBook(2)]))
        }
        let store = TestStore(initialState: state) { BookShelfMapFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSinceReferenceDate: 0)
        }
        store.exhaustivity = .off

        await store.send(\.details[id: book.id].favoriteButtonTapped)

        #expect(store.state.details[id: book.id]?.isFavorite == true)
        #expect(store.state.details[id: makeBook(2).id]?.isFavorite == false)
    }
}
