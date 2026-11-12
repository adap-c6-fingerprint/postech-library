import Foundation
@testable import fingerprint_library

/// 테스트용 도서. 제어번호가 있으면 recordKey가 제어번호로 정해진다.
@MainActor
func makeBook(_ number: Int, imageURL: URL? = nil) -> Book {
    Book(
        id: "primo:\(number)", isbn: nil, controlNumber: "primo:\(number)",
        title: "책 \(number)", author: "저자", publisher: nil, publicationYear: nil,
        description: nil, imageURL: imageURL
    )
}
