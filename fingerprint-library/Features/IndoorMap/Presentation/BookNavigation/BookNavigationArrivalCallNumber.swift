import Foundation

/// 책등에서 먼저 찾을 분류 숫자를 분리한다. 나머지 기호는 생략·재해석하지 않는다.
struct BookNavigationArrivalCallNumber: Equatable {
    let rawValue: String
    let classification: String
    let number: String
    let suffix: String

    init?(_ value: String) {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let classRange = raw.range(of: "^[A-Za-z]+", options: .regularExpression) else { return nil }
        let rest = raw[classRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numberRange = rest.range(of: "^[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) else { return nil }
        rawValue = raw
        classification = String(raw[classRange])
        number = String(rest[numberRange])
        suffix = rest[numberRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
