/// 길안내 한 번에 전달할 수 있는 책 수. 책바구니 보관 수량과는 별개다.
nonisolated enum BookRouteSelection {
    static let maximumBookCount = 3

    static func allows(bookCount: Int) -> Bool {
        (1...maximumBookCount).contains(bookCount)
    }
}
