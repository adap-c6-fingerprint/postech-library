import Foundation

/// PLI-96 내부 알파용 고정 목적지. 소장 정보는 API 응답이 아닌 사용자 제공 목데이터다.
enum BookRoutePreviewSample {
    static let recordID = "alma991003794555103286"
    static let book = Book(
        id: "primo:\(recordID)", isbn: nil, controlNumber: "primo:\(recordID)",
        title: "동물농장", author: "George Orwell · 김승욱", publisher: nil,
        publicationYear: nil, description: nil, imageURL: nil
    )
    static let holding = BookHolding(
        holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
        locationCode: "c3b", locationName: "박태준학술정보관 단행본3층",
        callNumber: "PR6029.R8 .O79 2021", availability: nil
    )
}
