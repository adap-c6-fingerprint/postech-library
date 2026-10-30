import Foundation

/// PLI-96 내부 알파용 고정 목적지. 소장 정보는 API 응답이 아닌 사용자 제공 목데이터다.
enum BookRoutePreviewSample {
    static let testItems = [
        item(recordID: "alma991000841739703286", title: "인물 과학사", author: "박성래, 1939-",
             year: "2011", callNumber: "Q141 .박54 2011"),
        item(recordID: "alma991000972219703286", title: "미움받을 용기 2 : 사랑과 진정한 자립에 대한 아들러의 가르침",
             author: "안견일랑; 岸見一郞; 古賀史健; 고하사건; 전경아; 기시미 이치로; 고가 후미타케",
             year: "2016", callNumber: "BF637.S4 .안141 2016"),
        item(recordID: "alma991000569859703286", title: "노르웨이의 숲", author: "무라카미, 하루키; 촌상, 춘수; 이미라, 옮김",
             year: "1993", callNumber: "PL833.U73 .노29 1993")
    ]

    private static func item(recordID: String, title: String, author: String, year: String,
                             callNumber: String) -> (book: Book, holding: BookHolding) {
        (Book(id: "primo:\(recordID)", isbn: nil, controlNumber: "primo:\(recordID)", title: title, author: author,
              publisher: nil, publicationYear: year, description: nil, imageURL: nil),
         BookHolding(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                     locationCode: "c3b", locationName: "박태준학술정보관 단행본3층", callNumber: callNumber, availability: nil))
    }

    // 기존 단일 목적지 경로의 회귀 검증 자료는 보존한다. 테스트모드 버튼에서는 사용하지 않는다.
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
