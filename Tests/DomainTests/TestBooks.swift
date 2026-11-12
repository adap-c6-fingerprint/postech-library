import Foundation
@testable import fingerprint_library

@MainActor
func makeBook(_ number: Int, imageURL: URL? = nil) -> Book {
    Book(
        id: "primo:\(number)", isbn: nil, controlNumber: "primo:\(number)",
        title: "책 \(number)", author: "저자", publisher: nil, publicationYear: nil,
        description: nil, imageURL: imageURL
    )
}
