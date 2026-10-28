import Foundation

/// 실제 POSTECH 응답의 최상위 delivery를 우선한다. 문서의 pnx.delivery와 PNX 대체 표기도 수용한다.
nonisolated enum PrimoHoldingsMapper {
    static func decode(_ data: Data, recordID: String) throws -> [BookHolding] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let document = response.docs.first(where: { $0.pnx.control.recordid.contains(recordID) }) else {
            return []
        }
        // 명시적인 빈 holding 목록은 소장 정보 없음이다. 대체 필드로 과거 위치를 되살리지 않는다.
        let delivery = document.delivery ?? document.pnx.delivery
        if let holdings = delivery?.holding { return unique(holdings.map(\.value)) }
        if let best = delivery?.bestlocation { return [best.value] }
        return unique((document.pnx.display?.availlibrary ?? []).compactMap(parseAvailability))
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
        // 공식 PNX: I=기관, L=도서관, 1=소장 위치, 2=청구기호, S=상태, Z=위치 코드.
        guard fields["9"] != "ONLINE", fields["2"] != nil else { return nil }
        return .init(holdingID: fields["J"], institutionCode: fields["I"], libraryCode: fields["L"],
                     locationCode: fields["Z"], locationName: fields["1"], callNumber: fields["2"],
                     availability: fields["S"])
    }

    private struct Response: Decodable { let docs: [Document] }
    private struct Document: Decodable {
        let pnx: PNX
        let delivery: Delivery?
    }
    private struct PNX: Decodable {
        let control: Control
        let display: Display?
        let delivery: Delivery?
    }
    private struct Control: Decodable { let recordid: [String] }
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
