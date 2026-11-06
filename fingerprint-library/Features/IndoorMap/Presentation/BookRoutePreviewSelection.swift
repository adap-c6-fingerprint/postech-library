/// 버튼과 카드가 책의 ID로 같은 선택을 공유한다. 제목·방문 순서가 바뀌어도 선택한 책을 유지한다.
nonisolated struct BookRoutePreviewSelection: Equatable {
    private(set) var selectedBookID: Book.ID?

    func bookID(in books: [Book]) -> Book.ID? {
        if let selectedBookID, books.contains(where: { $0.id == selectedBookID }) {
            return selectedBookID
        }
        return books.first?.id
    }

    mutating func select(_ bookID: Book.ID?, in books: [Book]) {
        guard let bookID, books.contains(where: { $0.id == bookID }) else { return }
        selectedBookID = bookID
    }

    mutating func reconcile(with books: [Book]) {
        if let selectedBookID, !books.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = nil
        }
    }
}
