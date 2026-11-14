struct BookRoutePreviewDestination: Equatable {
    private(set) var books: [Book]

    init(books: [Book]) {
        self.books = books
    }
}
