import Testing
@testable import fingerprint_library

struct BookISBNAndTextTests {
    @Test("ISBN13을 우선하고 하이픈과 ISBN10을 처리한다", arguments: [
        ("978-89-6626-095-9", "9788966260959"),
        ("0131103628 9788966260959", "9788966260959"),
        ("0-13-110362-8", "9780131103627"),
        ("097522980X", "9780975229804")
    ])
    func normalizeISBN(sample: (String, String)) {
        #expect(BookISBN.isbn13(from: sample.0) == sample.1)
    }

    @Test("ISBN이 없거나 체크 숫자가 틀리면 요청할 ISBN을 만들지 않는다", arguments: [
        nil, "", "9788966260950", "0131103620", "9788966260959garbage"
    ] as [String?])
    func invalidISBN(value: String?) {
        #expect(BookISBN.isbn13(from: value) == nil)
    }

    @Test("문단과 HTML 문자 참조를 보존하고 스크립트와 강조 태그를 제거한다")
    func plainText() {
        let html = "<style>p{color:red}</style><p><span>책</span>&nbsp;&#49548;&#xAC1C;</p><p>&lt;Swift&gt; &amp; &quot;TCA&quot;</p><script>alert(1)</script>"
        #expect(BookText.plainText(html) == "책 소개\n<Swift> & \"TCA\"")
        #expect(BookText.plainText("평문\n\n두 번째 문단") == "평문\n\n두 번째 문단")
    }
}
