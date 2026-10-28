import Foundation
@testable import fingerprint_library

enum BookHoldingTestData {
    static let calls = ["RC263 .R632 1990", "T100 .A1 2020", "TA410 .A1 2020"]

    static func holding(_ index: Int = 0, code: String = "c3b", call: String? = nil) -> BookHolding {
        .init(holdingID: "holding-\(index)-\(code)", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
              locationCode: code, locationName: code == "c3b" ? "단행본3층" : "제본학술지4층",
              callNumber: call ?? calls[index % calls.count], availability: "available")
    }

    static func book(_ index: Int = 0) -> Book {
        .init(id: "route-book-\(index)", isbn: nil, controlNumber: "primo:alma99100095875970328\(index)",
              title: "서가 위치 테스트 도서 \(index + 1)", author: "테스트", publisher: nil,
              publicationYear: nil, description: nil, imageURL: nil)
    }
}
