import Foundation

nonisolated struct BookCardLibraryInfo: Equatable, Sendable {
    enum Availability: Equatable, Sendable { case available, unavailable, unknown }

    let holdings: [BookHolding]

    var primaryHolding: BookHolding? {
        let local = holdings.filter { $0.institutionCode == "82POSTECH_INST" && $0.libraryCode == "MAIN" }
        let candidates = local.isEmpty ? holdings : local
        return candidates.first { $0.availability == "available" }
            ?? candidates.first { $0.availability == "unavailable" }
            ?? candidates.first
    }

    var location: String? {
        guard let holding = primaryHolding else { return nil }
        let name = holding.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.map {
            $0.hasPrefix("단행본") ? String($0.dropFirst("단행본".count)) : $0
        }
        let parts = [displayName, holding.callNumber].compactMap { value -> String? in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var availability: Availability {
        switch primaryHolding?.availability {
        case "available": .available
        case "unavailable": .unavailable
        default: .unknown
        }
    }

    var additionalLocationCount: Int {
        guard let primaryHolding else { return 0 }
        let locations = Set(holdings.map { [$0.institutionCode, $0.libraryCode, $0.locationCode, $0.locationName] })
        let primary = [primaryHolding.institutionCode, primaryHolding.libraryCode, primaryHolding.locationCode, primaryHolding.locationName]
        return locations.subtracting([primary]).count
    }
}
