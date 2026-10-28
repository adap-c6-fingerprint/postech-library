import Foundation
import ComposableArchitecture

nonisolated struct BookHoldingsClient: Sendable {
    var fetch: @Sendable (Book) async throws -> BookHolding?
}

extension BookHoldingsClient: DependencyKey {
    static let liveValue = Self(fetch: { try await PrimoBookHoldingsService().fetch(for: $0) })
    static let testValue = Self(fetch: { _ in nil })
}

extension DependencyValues {
    var bookHoldingsClient: BookHoldingsClient {
        get { self[BookHoldingsClient.self] }
        set { self[BookHoldingsClient.self] = newValue }
    }
}

/// POSTECH Primo 검색 화면의 공개 소장정보. 인증정보를 읽거나 전송하지 않는다.
nonisolated struct PrimoBookHoldingsService: Sendable {
    var load: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    func fetch(for book: Book) async throws -> BookHolding? {
        if let recordID = Self.recordID(book.controlNumber) ?? Self.recordID(book.id) {
            let docs = try await search(query: "any,contains,\(recordID.dropFirst(4))")
            let matching = docs.filter { $0.pnx.control.recordid.contains(recordID) }
            if let holding = Self.preferredHolding(in: matching) { return holding }
        }

        // 같은 ISBN이 소장 없음/실물 소장 레코드로 나뉜 경우, 동일 판본의 실물 소장을 찾는다.
        guard let isbn = BookISBN.isbn13(from: book.isbn) else { return nil }
        let docs = try await search(query: "isbn,exact,\(isbn)")
        let matching = docs.filter { doc in
            doc.pnx.addata?.isbn?.contains { BookISBN.isbn13(from: $0) == isbn } == true
        }
        return Self.preferredHolding(in: matching)
    }

    private func search(query: String) async throws -> [Document] {
        var components = URLComponents(
            string: "https://postech.primo.exlibrisgroup.com/primaws/rest/external/pnxs"
        )
        components?.queryItems = [
            URLQueryItem(name: "vid", value: "82POSTECH_INST:82POSTECH"),
            URLQueryItem(name: "tab", value: "LibraryCatalog"),
            URLQueryItem(name: "scope", value: "MyInstitution"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "multiFacets", value: "facet_rtype,include,books|,|facet_rtype,include,printed_book"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "lang", value: "ko"),
            URLQueryItem(name: "skipDelivery", value: "false")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await load(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data).docs
    }

    private static func recordID(_ value: String?) -> String? {
        guard var value = cleaned(value) else { return nil }
        if value.hasPrefix("primo:") { value.removeFirst(6) }
        if value.hasPrefix("alma") { value.removeFirst(4) }
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return "alma" + value
    }

    private static func preferredHolding(in docs: [Document]) -> BookHolding? {
        let holdings = docs.flatMap { doc -> [BookHolding] in
            guard let recordID = doc.pnx.control.recordid.first, let delivery = doc.delivery,
                  delivery.deliveryCategory?.contains("Alma-P") != false else { return [] }
            var locations = delivery.holding ?? []
            if locations.isEmpty, let best = delivery.bestlocation { locations = [best] }
            return locations.map { item in
                let availability: BookHolding.Availability
                switch item.availabilityStatus?.lowercased() {
                case "available": availability = .available
                case "unavailable": availability = .unavailable
                default: availability = .unknown
                }
                return BookHolding(
                    recordID: recordID, callNumber: cleaned(item.callNumber),
                    location: cleaned(item.subLocation), locationCode: cleaned(item.subLocationCode),
                    availability: availability
                )
            }
        }
        // 대출 가능한 실물 소장을 먼저 표시한다. 청구기호는 그 소장의 값만 사용한다.
        func rank(_ holding: BookHolding) -> Int {
            switch holding.availability {
            case .available: return 0
            case .unknown: return 1
            case .unavailable: return 2
            }
        }
        return holdings.enumerated().min {
            let lhs = (rank($0.element), $0.element.callNumber == nil ? 1 : 0, $0.offset)
            let rhs = (rank($1.element), $1.element.callNumber == nil ? 1 : 0, $1.offset)
            return lhs < rhs
        }?.element
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private struct Response: Decodable { let docs: [Document] }
    private struct Document: Decodable { let pnx: PNX; let delivery: Delivery? }
    private struct PNX: Decodable { let control: Control; let addata: AddData? }
    private struct Control: Decodable { let recordid: [String] }
    private struct AddData: Decodable { let isbn: [String]? }
    private struct Delivery: Decodable {
        let deliveryCategory: [String]?
        let holding: [Holding]?
        let bestlocation: Holding?
    }
    private struct Holding: Decodable {
        let callNumber: String?
        let subLocation: String?
        let subLocationCode: String?
        let availabilityStatus: String?
    }
}
