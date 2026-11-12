import Foundation

nonisolated enum PrimoHoldingsMapper {
    static func decode(_ data: Data, recordID: String) throws -> [BookHolding] {
        try decodeAll(data)[recordID] ?? []
    }

    static func decodeAll(_ data: Data) throws -> [String: [BookHolding]] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var result: [String: [BookHolding]] = [:]
        for document in response.docs {
            guard let pnx = document.pnx else { continue }
            guard let holdings = holdings(in: document, pnx: pnx) else { continue }
            for recordID in pnx.control?.recordid ?? [] where result[recordID] == nil {
                result[recordID] = holdings
            }
        }
        return result
    }

    private static func holdings(in document: Document, pnx: PNX) -> [BookHolding]? {
        let delivery = document.delivery ?? pnx.delivery
        if let holdings = delivery?.holding { return unique(holdings.map(\.value)) }
        if let best = delivery?.bestlocation { return [best.value] }
        guard let availability = pnx.display?.availlibrary else { return nil }
        return unique(availability.compactMap(parseAvailability))
    }

    private static func unique(_ holdings: [BookHolding]) -> [BookHolding] {
        var seen = Set<String>()
        return holdings.filter { seen.insert($0.id).inserted }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func parseAvailability(_ text: String) -> BookHolding? {
        var fields: [String: String] = [:]
        for part in text.components(separatedBy: "$$").dropFirst() {
            guard let key = part.first else { continue }
            fields[String(key)] = clean(String(part.dropFirst()))
        }
        guard fields["9"] != "ONLINE", fields["2"] != nil else { return nil }
        return .init(holdingID: fields["J"], institutionCode: fields["I"], libraryCode: fields["L"],
                     locationCode: fields["Z"], locationName: fields["1"], callNumber: fields["2"],
                     availability: fields["S"])
    }

    private struct Response: Decodable { let docs: [Document] }
    private struct Document: Decodable {
        let pnx: PNX?
        let delivery: Delivery?
    }
    private struct PNX: Decodable {
        let control: Control?
        let display: Display?
        let delivery: Delivery?
    }
    private struct Control: Decodable { let recordid: [String]? }
    private struct Display: Decodable { let availlibrary: [String]? }
    private struct Delivery: Decodable {
        let holding: [Holding]?
        let bestlocation: Holding?
    }
    private struct Holding: Decodable {
        let organization: String?
        let libraryCode: String?
        let subLocation: String?
        let subLocationCode: String?
        let subLocationCodeName: String?
        let callNumber: String?
        let availabilityStatus: String?
        let holdId: String?
        let holdingId: String?

        var value: BookHolding {
            .init(holdingID: clean(holdId) ?? clean(holdingId), institutionCode: clean(organization),
                  libraryCode: clean(libraryCode), locationCode: clean(subLocationCode) ?? clean(subLocation),
                  locationName: clean(subLocationCodeName) ?? clean(subLocation), callNumber: clean(callNumber),
                  availability: clean(availabilityStatus))
        }
    }
}
