import Foundation
@testable import fingerprint_library

@MainActor
func makeBook(_ number: Int) -> Book {
    Book(
        id: "primo:\(number)", isbn: nil, controlNumber: "primo:\(number)",
        title: "책 \(number)", author: "저자", publisher: nil, publicationYear: nil,
        description: nil, imageURL: nil
    )
}

@MainActor
func makeCartItems(_ numbers: [Int]) -> [BookCartItem] {
    numbers.map { BookCartItem(book: makeBook($0), addedAt: Date(timeIntervalSinceReferenceDate: 0)) }
}
