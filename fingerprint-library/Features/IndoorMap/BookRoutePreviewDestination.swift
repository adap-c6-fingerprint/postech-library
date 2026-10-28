/// 이전 페이지의 도서 입력과 사용자가 명시적으로 선택한 테스트 모드를 구분한다.
struct BookRoutePreviewDestination: Equatable {
    private(set) var books: [Book]
    private(set) var isAnimalFarmTest = false

    init(books: [Book]) {
        self.books = books
    }

    mutating func useAnimalFarmTest() {
        books = [BookRoutePreviewSample.book]
        isAnimalFarmTest = true
    }
}
