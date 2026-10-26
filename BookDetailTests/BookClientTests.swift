import Testing
@testable import fingerprint_library

struct BookClientTests {
    @Test("Primo 날짜에서 네 자리 출판 연도만 추출한다", arguments: [
        ("2011", "2011"),
        (" 2011\n", "2011"),
        ("c2011", "2011"),
        ("©2011", "2011"),
        ("[2011]", "2011"),
        ("2011년", "2011"),
        ("2011-2013", "2011")
    ])
    func publicationYear(sample: (String, String)) {
        #expect(BookClient.publicationYear(from: sample.0) == sample.1)
    }

    @Test("유효한 네 자리 연도가 없으면 출판 연도를 저장하지 않는다", arguments: [
        nil, "", " \n", "n.d.", "20??", "201", "0000", "12011", "20110", "20112012"
    ] as [String?])
    func invalidPublicationYear(value: String?) {
        #expect(BookClient.publicationYear(from: value) == nil)
    }

    @Test("공백 출판사는 건너뛰고 유효한 pub를 우선한다", arguments: [
        (nil, nil, nil),
        ([], [], nil),
        (["", " \n"], ["", " "], nil),
        (["주 출판사"], ["대체 출판사"], "주 출판사"),
        ([" 주 출판사 "], ["대체 출판사"], "주 출판사"),
        ([" ", " "], ["대체 출판사"], "대체 출판사"),
        (["", ""], ["대체 출판사"], "대체 출판사"),
        (nil, [" 대체 출판사 "], "대체 출판사"),
        ([], ["", " 대체 출판사 ", " "], "대체 출판사"),
        (["", " 주 출판사 ", " "], ["대체 출판사"], "주 출판사"),
        ([" 첫 출판사 ", "", "두 번째 출판사 "], nil, "첫 출판사, 두 번째 출판사")
    ] as [([String]?, [String]?, String?)])
    func publisher(sample: ([String]?, [String]?, String?)) {
        #expect(BookClient.publisher(from: sample.0, fallback: sample.1) == sample.2)
    }
}
