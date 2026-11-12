import Foundation

/// 책등에서 먼저 찾을 분류 숫자를 분리한다. 나머지 기호는 생략·재해석하지 않는다.
nonisolated struct BookNavigationArrivalCallNumber: Equatable {
    let rawValue: String
    let classification: String
    let number: String
    let suffix: String

    /// 번호표는 최대 세 줄을 사용하며 연도·권차 등 남은 기호는 마지막 줄에 함께 보존한다.
    var stickerLines: [String] {
        let first = classification + number
        let parts = suffix.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let second = parts.first else { return [first] }
        guard parts.count > 1 else { return [first, second] }
        return [first, second, parts.dropFirst().joined(separator: " ")]
    }

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
