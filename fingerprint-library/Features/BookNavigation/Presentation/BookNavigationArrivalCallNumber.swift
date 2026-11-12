import Foundation

nonisolated struct BookNavigationArrivalCallNumber: Equatable {
    let rawValue: String
    let classification: String
    let number: String
    let suffix: String

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
