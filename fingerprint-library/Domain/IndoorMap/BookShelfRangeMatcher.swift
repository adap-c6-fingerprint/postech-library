import Foundation

/// 범위 조회에 사용할 소장본 하나의 위치. 지도 ordinal은 실제 층 번호에서 1을 뺀 값이다.
nonisolated struct BookShelfLocation: Equatable, Sendable {
    let floorNumber: Int
    let callNumber: String
}

/// 임시 서가 후보 조회. 층을 먼저 제한하고 양 끝을 포함해 겹치는 후보를 모두 보존한다.
/// 도착 노드나 확정된 ShelfDestination을 만들지 않는다.
nonisolated struct BookShelfRangeMatcher {
    func candidates(for location: BookShelfLocation, on map: IndoorMap,
                    labels: [IndoorShelfLabel]) -> [IndoorShelfLabel] {
        guard let floor = map.floors.first(where: { $0.ordinal == location.floorNumber - 1 }),
              let call = CallNumber(location.callNumber) else { return [] }
        return labels.filter { label in
            guard label.floorID == floor.id,
                  case .callNumberRange(let start, let end) = label.content,
                  let lower = CallNumber(start), let upper = CallNumber(end) else { return false }
            // 서가의 마지막 표기가 전체 청구기호의 접두어이면 같은 분류의 연도·권차도 후보로 둔다.
            return lower.compare(to: call) != .orderedDescending
                && (call.compare(to: upper) != .orderedDescending || upper.isPrefix(of: call))
        }
    }

    /// 분류 번호는 수치, 저자 기호의 숫자는 소수로 비교한다. 연도·권차는 범위 판정에 사용하지 않는다.
    private struct CallNumber {
        let classification: String
        let number: Decimal
        let cutters: [String]

        init?(_ value: String) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let match = text.range(of: #"^[A-Z]{1,3}\s*[0-9]+(?:\.[0-9]+)?"#,
                                         options: .regularExpression) else { return nil }
            let head = String(text[match]).replacingOccurrences(of: " ", with: "")
            classification = String(head.prefix(while: { $0.isLetter }))
            guard let number = Decimal(string: String(head.dropFirst(classification.count)),
                                       locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            self.number = number
            let tail = String(text[match.upperBound...])
            // 영문·한글 저자 기호를 보존하고 공백으로 구분된 연도·권차 앞에서 멈춘다.
            let pattern = #"^\s*\.?\s*([\p{L}]+[0-9]+)"#
            let regex = try! NSRegularExpression(pattern: pattern)
            var rest = tail
            var cutters: [String] = []
            while let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let token = Range(match.range(at: 1), in: rest),
                  let consumed = Range(match.range, in: rest) {
                cutters.append(String(rest[token]))
                rest = String(rest[consumed.upperBound...])
            }
            // 임시 비교가 해석하지 못한 표기를 임의의 서가에 배정하지 않는다.
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
                // Cutter 숫자는 .12 < .2이므로 숫자 정렬을 사용하지 않는다.
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
