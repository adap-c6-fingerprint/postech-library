import Foundation

nonisolated enum BookISBN {
    /// 도서관 응답에 여러 ISBN이 있으면 ISBN13을 우선하고 ISBN10은 변환한다.
    static func isbn13(from value: String?) -> String? {
        guard let value else { return nil }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",;/()[]:"))
        let candidates = value.components(separatedBy: separators)
            .map { $0.replacingOccurrences(of: "-", with: "").uppercased() }
        if let isbn = candidates.first(where: isValidISBN13) { return isbn }
        guard let isbn10 = candidates.first(where: isValidISBN10) else { return nil }
        let prefix = "978" + isbn10.prefix(9)
        return prefix + String(checkDigit(for: prefix))
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13, value.hasPrefix("978") || value.hasPrefix("979"),
              value.allSatisfy({ $0.isASCII && $0.isNumber }),
              let last = value.last?.wholeNumberValue else { return false }
        return checkDigit(for: String(value.prefix(12))) == last
    }

    private static func checkDigit(for prefix: String) -> Int {
        let sum = prefix.enumerated().reduce(0) {
            $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - sum % 10) % 10
    }

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        var sum = 0
        for (index, character) in value.enumerated() {
            if index == 9 && character == "X" {
                sum += 10
            } else if character.isASCII, let digit = character.wholeNumberValue {
                sum += digit * (10 - index)
            } else {
                return false
            }
        }
        return sum.isMultiple(of: 11)
    }
}
