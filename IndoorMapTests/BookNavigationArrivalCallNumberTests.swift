import Testing
@testable import fingerprint_library

struct BookNavigationArrivalCallNumberTests {
    @Test("분류 문자·첫 숫자·나머지 기호를 원문 순서로 보존한다", arguments: [
        ["QA76.73 .P98 2021", "QA", "76.73", ".P98 2021"],
        ["PR6029.R8 .O79 2021", "PR", "6029", ".R8 .O79 2021"],
        ["PL833.U73 .노29 1993", "PL", "833", ".U73 .노29 1993"],
        [" Q 141 .박54 2011 \n", "Q", "141", ".박54 2011"],
        ["QA42", "QA", "42", ""]
    ])
    func preservesComponents(parts: [String]) throws {
        let number = try #require(BookNavigationArrivalCallNumber(parts[0]))
        #expect(number.classification == parts[1])
        #expect(number.number == parts[2])
        #expect(number.suffix == parts[3])
        #expect(number.rawValue == parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("구조를 알 수 없는 청구기호에 강조 숫자를 지어내지 않는다", arguments: ["", "QA", "76.73", "참고 QA76", "DVD-42"])
    func rejectsUnknownFormats(rawValue: String) {
        #expect(BookNavigationArrivalCallNumber(rawValue) == nil)
    }
}
