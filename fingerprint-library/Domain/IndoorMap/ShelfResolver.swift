import Foundation

nonisolated struct ShelfResolution: Equatable, Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case unsupportedLocation
        case missingCallNumber
        case outsideIndex
        case candidates([IndoorShelfLabel])
    }
    enum Area: Equatable, Sendable {
        case generalStack
        case displayShelf
        case namedShelf
    }
    var id: String { holding.id }
    let holding: BookHolding
    let area: Area?
    let outcome: Outcome
    var shelves: [IndoorShelfLabel] {
        guard case .candidates(let shelves) = outcome else { return [] }
        return shelves
    }
}

nonisolated extension Array where Element == ShelfResolution {
    var preferredForRoute: [ShelfResolution] {
        let hasGeneralStack = contains { $0.area == .generalStack && !$0.shelves.isEmpty }
        guard hasGeneralStack else { return self }
        return filter { $0.area == .generalStack }
    }

    var preferredRouteShelves: [IndoorShelfLabel] {
        var seen = Set<String>()
        return preferredForRoute.flatMap(\.shelves).filter { seen.insert($0.id).inserted }
    }
}

nonisolated struct ShelfResolver {
    func resolve(_ holdings: [BookHolding], on map: IndoorMap,
                 labels: [IndoorShelfLabel]) -> [ShelfResolution] {
        holdings.map { resolve($0, on: map, labels: labels) }
    }

    private func resolve(_ holding: BookHolding, on map: IndoorMap,
                         labels: [IndoorShelfLabel]) -> ShelfResolution {
        guard holding.institutionCode == "82POSTECH_INST", holding.libraryCode == "MAIN" else {
            return .init(holding: holding, area: nil, outcome: .unsupportedLocation)
        }
        let code = holding.locationCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if let floor = ["c3b": 3, "c4b": 4][code] {
            guard let call = holding.callNumber, !call.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(holding: holding, area: .generalStack, outcome: .missingCallNumber)
            }
            let shelves = BookShelfRangeMatcher().candidates(
                for: .init(floorNumber: floor, callNumber: call), on: map, labels: labels
            )
            return .init(holding: holding, area: .generalStack,
                         outcome: shelves.isEmpty ? .outsideIndex : .candidates(shelves))
        }
        let compactName = holding.locationName?.precomposedStringWithCanonicalMapping
            .uppercased().filter { !$0.isWhitespace } ?? ""
        let usesNameFallback = !["c2n", "c2sb2", "c2e"].contains(code)
        let name: String
        let area: ShelfResolution.Area
        if code == "c2n" || (usesNameFallback && ["신착서가(2층)", "신착서가(2F)"].contains(compactName)) {
            guard let call = holding.callNumber, !call.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(holding: holding, area: .namedShelf, outcome: .missingCallNumber)
            }
            guard let shelfName = Self.newArrivalShelfName(for: call) else {
                return .init(holding: holding, area: .namedShelf, outcome: .outsideIndex)
            }
            name = shelfName
            area = .namedShelf
        } else if code == "c2sb2" {
            name = "원형서가 B"
            area = .namedShelf
        } else if code == "c2e" || (usesNameFallback && ["영어교양2층", "영어교양(2층)", "영어교양(2F)"].contains(compactName)) {
            name = "영어 교양 서가"
            area = .namedShelf
        } else if let shelfName = Self.circularShelfName(in: holding.locationName) {
            name = shelfName
            area = .namedShelf
        } else if let shelfName = Self.displayShelfName(in: holding.locationName) {
            name = shelfName
            area = .displayShelf
        } else {
            return .init(holding: holding, area: nil, outcome: .unsupportedLocation)
        }
        let shelves = labels.filter { label in
            guard case .category(let category) = label.content else { return false }
            return category == name
                && map.floors.first(where: { $0.id == label.floorID })?.ordinal == 1
        }
        return .init(holding: holding, area: area,
                     outcome: shelves.isEmpty ? .outsideIndex : .candidates(shelves))
    }

    static func displayShelfName(in locationName: String?) -> String? {
        guard let text = locationName?.precomposedStringWithCanonicalMapping.uppercased(),
              let match = text.firstMatch(of: /(?:삼각\s*서가|DISPLAY\s*SHELF)\s*([ABCD])(?:[^A-Z]|$)/) else { return nil }
        let letter = match.1 == "D" ? "B" : String(match.1)
        return "삼각서가 \(letter)"
    }

    private static func circularShelfName(in locationName: String?) -> String? {
        guard let text = locationName?.precomposedStringWithCanonicalMapping.uppercased(),
              let match = text.firstMatch(of: /(?:원형\s*서가|SPECIAL\s+COLLECTION)\s*(?:\(\s*2\s*(?:F|층)\s*\)\s*)?([AB])(?:[^A-Z]|$)/) else {
            return nil
        }
        return "원형서가 \(match.1)"
    }

    private static func newArrivalShelfName(for callNumber: String) -> String? {
        let text = callNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let match = text.firstMatch(of: /^([A-Z]{1,3})\s*[0-9]/) else { return nil }
        // 상한 다음 대분류를 사용해 DS는 후자에, PL·PN 등 P 하위 분류는 HN-P에 포함한다.
        let suffix: String
        switch String(match.1) {
        case "A"..<"DS": suffix = "A-DS"
        case "DS"..<"H": suffix = "DS-G"
        case "H"..<"HN": suffix = "H-HM"
        case "HN"..<"Q": suffix = "HN-P"
        default: return nil
        }
        return "신착서가 \(suffix)"
    }
}
