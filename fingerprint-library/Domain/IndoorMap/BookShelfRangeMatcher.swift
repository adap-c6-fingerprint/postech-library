import Foundation

nonisolated struct BookShelfLocation: Equatable, Sendable {
    let floorNumber: Int
    let callNumber: String
}

nonisolated struct BookShelfRangeMatcher {
    func candidates(for location: BookShelfLocation, on map: IndoorMap,
                    labels: [IndoorShelfLabel]) -> [IndoorShelfLabel] {
        guard let floor = map.floors.first(where: { $0.ordinal == location.floorNumber - 1 }),
              let call = CallNumber(location.callNumber) else { return [] }
        return labels.filter { label in
            guard label.floorID == floor.id,
                  case .callNumberRange(let start, let end) = label.content,
                  let lower = CallNumber(start), let upper = CallNumber(end) else { return false }
            return lower.compare(to: call) != .orderedDescending
                && (call.compare(to: upper) != .orderedDescending || upper.isPrefix(of: call))
        }
    }

    private struct CallNumber {
        private static let cutterRegex = try! NSRegularExpression(
            pattern: #"^\s*\.?\s*([\p{L}]+[0-9]+|[가-힣]+(?=\s*\.))"#
        )

        let classification: String
        let number: Decimal
        let cutters: [String]

        init?(_ value: String) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping.uppercased()
            guard let match = text.range(of: #"^[A-Z]{1,3}\s*[0-9]+(?:\.[0-9]+)?"#,
                                         options: .regularExpression) else { return nil }
            let head = String(text[match]).replacingOccurrences(of: " ", with: "")
            classification = String(head.prefix(while: { $0.isLetter }))
            guard let number = Decimal(string: String(head.dropFirst(classification.count)),
                                       locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            self.number = number
            let tail = String(text[match.upperBound...])
            var rest = tail
            var cutters: [String] = []
            while let match = Self.cutterRegex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let token = Range(match.range(at: 1), in: rest),
                  let consumed = Range(match.range, in: rest) {
                cutters.append(String(rest[token]))
                rest = String(rest[consumed.upperBound...])
            }
            let suffix = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard suffix.isEmpty || suffix.range(of: #"^(?:[0-9]{4}(?:\D|$)|[vVcC]\.|권|복본)"#,
                                                 options: .regularExpression) != nil else { return nil }
            self.cutters = cutters
        }

        func compare(to other: Self) -> ComparisonResult {
            if classification != other.classification {
                return classification < other.classification ? .orderedAscending : .orderedDescending
            }
            if number != other.number { return number < other.number ? .orderedAscending : .orderedDescending }
            for (left, right) in zip(cutters, other.cutters) where left != right {
                let leftIsKorean = left.range(of: #"^[가-힣]"#, options: .regularExpression) != nil
                let rightIsKorean = right.range(of: #"^[가-힣]"#, options: .regularExpression) != nil
                if leftIsKorean != rightIsKorean {
                    return leftIsKorean ? .orderedAscending : .orderedDescending
                }
                return left < right ? .orderedAscending : .orderedDescending
            }
            if cutters.count == other.cutters.count { return .orderedSame }
            return cutters.count < other.cutters.count ? .orderedAscending : .orderedDescending
        }

        func isPrefix(of other: Self) -> Bool {
            classification == other.classification && number == other.number
                && other.cutters.starts(with: cutters)
        }
    }
}
