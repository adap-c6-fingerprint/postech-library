import Foundation

nonisolated struct PrimoCandidatePage: Equatable, Sendable {
    let total: Int
    let candidates: [ColdStartCandidate]
}

/// Primo 전송 형식과 추천 서비스의 후보 모델 사이의 변환 경계.
nonisolated enum PrimoRecommendationMapper {
    static func coldStartPage(from data: Data, codes: [String]) throws -> PrimoCandidatePage {
        let response = try JSONDecoder().decode(ColdStartResponse.self, from: data)
        var seen = Set<String>()
        let candidates = response.docs.compactMap { doc -> ColdStartCandidate? in
            guard let recordID = doc.pnx.control.recordid.first, !recordID.isEmpty,
                  seen.insert(recordID).inserted else { return nil }
            let callNumbers = doc.delivery?.holding?.compactMap(\.callNumber) ?? []
            guard callNumbers.contains(where: {
                ColdStartRecommendation.callNumber($0, matchesAnyOf: codes)
            }) else { return nil }
            let cover = thumbnailURL(from: doc.delivery?.link)
            let isbn = BookISBN.isbn13(from: doc.pnx.addata?.isbn?.joined(separator: " "))
            guard cover != nil || isbn != nil else { return nil }
            return ColdStartCandidate(recordID: recordID, primoCoverURL: cover, isbn13: isbn)
        }
        return PrimoCandidatePage(total: response.info.total, candidates: candidates)
    }

    static func titles(from data: Data) throws -> [String] {
        try JSONDecoder().decode(PersonalizedResponse.self, from: data).docs.compactMap { doc in
            doc.pnx.display.title?.first.map(BookText.plainText).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    static func personalizedCandidates(from data: Data) throws -> [PersonalizedCandidate] {
        let response = try JSONDecoder().decode(PersonalizedResponse.self, from: data)
        var seen = Set<String>()
        return response.docs.compactMap { doc -> PersonalizedCandidate? in
            guard let recordID = doc.pnx.control.recordid.first, !recordID.isEmpty,
                  seen.insert(recordID).inserted else { return nil }
            guard let title = doc.pnx.display.title?.first.map(BookText.plainText), !title.isEmpty,
                  let callNumber = doc.delivery?.holding?
                    .compactMap({ $0.callNumber?.trimmingCharacters(in: .whitespaces) })
                    .first(where: { !$0.isEmpty }) else { return nil }
            let cover = thumbnailURL(from: doc.delivery?.link)
            let isbn = BookISBN.isbn13(from: doc.pnx.addata?.isbn?.joined(separator: " "))
            guard cover != nil || isbn != nil else { return nil }
            return PersonalizedCandidate(
                recordID: recordID, title: title, subject: doc.pnx.display.subject?.first.map(BookText.plainText),
                callNumber: callNumber, primoCoverURL: cover, isbn13: isbn
            )
        }
    }

    private static func thumbnailURL(from links: [Link]?) -> URL? {
        links?
            .filter { $0.linkType == "thumbnail" || $0.linkType?.hasSuffix("/thumbnail") == true }
            .compactMap { link -> URL? in
                guard let address = link.linkURL,
                      let parts = URLComponents(string: address)
                        ?? address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                            .flatMap(URLComponents.init(string:)),
                      parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty
                else { return nil }
                let isLookup = parts.queryItems?.contains { $0.name == "jscmd" && $0.value == "viewapi" } ?? false
                return isLookup ? nil : parts.url
            }
            .first
    }

    // 첫 추천에는 total이 필요하고 display는 필요 없다. 맞춤 추천은 display를 요구한다.
    // DTO를 구분해 기존의 누락 필드 처리 계약을 보존한다.
    private nonisolated struct ColdStartResponse: Decodable {
        let info: Info
        let docs: [ColdStartDocument]
    }
    private nonisolated struct Info: Decodable { let total: Int }
    private nonisolated struct ColdStartDocument: Decodable {
        let pnx: ColdStartPNX
        let delivery: Delivery?
    }
    private nonisolated struct ColdStartPNX: Decodable {
        let control: Control
        let addata: AddData?
    }
    private nonisolated struct PersonalizedResponse: Decodable { let docs: [PersonalizedDocument] }
    private nonisolated struct PersonalizedDocument: Decodable {
        let pnx: PersonalizedPNX
        let delivery: Delivery?
    }
    private nonisolated struct PersonalizedPNX: Decodable {
        let control: Control
        let display: Display
        let addata: AddData?
    }
    private nonisolated struct Control: Decodable { let recordid: [String] }
    private nonisolated struct AddData: Decodable { let isbn: [String]? }
    private nonisolated struct Display: Decodable {
        let title: [String]?
        let subject: [String]?
    }
    private nonisolated struct Delivery: Decodable {
        let holding: [Holding]?
        let link: [Link]?
    }
    private nonisolated struct Holding: Decodable { let callNumber: String? }
    private nonisolated struct Link: Decodable {
        let linkType: String?
        let linkURL: String?
    }
}
