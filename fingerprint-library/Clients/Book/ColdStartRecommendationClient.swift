//
//  ColdStartRecommendationClient.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

nonisolated struct ColdStartRecommendationClient: Sendable {
// 첫 추천 도서를 가져오는 창구.
    var fetch: @Sendable (_ interests: [String]) async throws -> [RecommendedBook]
    // 관심사를 넣으면 추천 도서(최대 6권)를 돌려준다.
}

extension ColdStartRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { interests in
        try await ColdStartRecommendationService.recommend(interests: interests)
    })
    // 실제 앱: 포스텍 API와 정보나루 API를 호출한다.
    static let testValue = Self(fetch: { _ in [] })
    // 테스트: 항상 빈 결과.
}

extension DependencyValues {
    var coldStartRecommendationClient: ColdStartRecommendationClient {
        get { self[ColdStartRecommendationClient.self] }
        set { self[ColdStartRecommendationClient.self] = newValue }
    }
}

nonisolated enum ColdStartRecommendationError: Error, Equatable {
    case noInterests
    // 쓸 수 있는 관심사가 하나도 없음.
    case missingPrimoAPIKey
    // 포스텍 API 키(PRIMO_API_KEY)가 설정되지 않음.
    case missingData4LibraryAPIKey
    // 정보나루 API 키(DATA4LIBRARY_API_KEY)가 설정되지 않음.
    case invalidURL
    // 요청 주소를 만들지 못함.
    case invalidResponse
    // 서버가 정상 응답(200번대)을 주지 않음.
}

nonisolated struct PrimoCandidatePage: Equatable, Sendable {
// 포스텍 응답 한 번을 해석한 결과.
    let total: Int
    // 조건에 맞는 전체 책 수. 무작위 위치를 고를 때 쓴다.
    let candidates: [ColdStartCandidate]
    // 조건을 통과한 후보.
}

nonisolated enum ColdStartRecommendationService {

    static func recommend(interests: [String]) async throws -> [RecommendedBook] {
    // 전체 흐름을 실행한다.
        let codes = ColdStartRecommendation.normalizedCodes(interests)
        guard !codes.isEmpty else { throw ColdStartRecommendationError.noInterests }
        guard let primoKey = await AppConfiguration.primoAPIKey else {
            throw ColdStartRecommendationError.missingPrimoAPIKey
        }
        guard let data4LibraryKey = await AppConfiguration.data4LibraryAPIKey else {
            throw ColdStartRecommendationError.missingData4LibraryAPIKey
        }

        let query = ColdStartRecommendation.primoQuery(for: codes)
        let first = try parsePrimo(
            try await searchPrimo(query: query, offset: 0, apiKey: primoKey),
            codes: codes
        )
        // ① 1차 요청. 50권과 전체 건수를 받는다.
        var generator = SystemRandomNumberGenerator()
        var result: [RecommendedBook] = []
        var usedRecordIDs = Set<String>()
        // 이미 확인한 책. 추가로 받아 온 결과에서 같은 책을 다시 확인하지 않는다.

        for _ in 0...ColdStartRecommendation.extraPageLimit {
        // 처음 한 번 + 표지가 모자랄 때 최대 extraPageLimit번 더.
            let offset = ColdStartRecommendation.randomOffset(total: first.total, using: &generator)
            let page = offset == 0
                ? first
                : try parsePrimo(try await searchPrimo(query: query, offset: offset, apiKey: primoKey), codes: codes)
            // ② 무작위 위치에서 50권. 위치가 0이면 1차 결과를 그대로 쓴다.
            let fresh = page.candidates.filter { usedRecordIDs.insert($0.recordID).inserted }.shuffled()
            // 처음 보는 책만 섞는다.
            result += await booksWithCovers(
                fresh,
                limit: ColdStartRecommendation.resultCount - result.count,
                data4LibraryLookup: { isbn13 in
                    try? await data4LibraryCoverURL(isbn13: isbn13, apiKey: data4LibraryKey)
                },
                isRealImage: isRealImage
            )
            // ③ 정보나루 → 4libs 순서로 표지를 확인해 모자란 만큼 채운다.
            if result.count >= ColdStartRecommendation.resultCount
                || first.total <= ColdStartRecommendation.primoFetchCount { break }
            // 6권을 채웠거나, 전체가 50권 이하라 더 받아 올 책이 없으면 끝.
        }
        return result
    }

    // MARK: - 표지 고르기

    static func booksWithCovers(
        _ candidates: [ColdStartCandidate],
        limit: Int = ColdStartRecommendation.resultCount,
        data4LibraryLookup: @escaping @Sendable (_ isbn13: String) async -> URL?,
        isRealImage: @escaping @Sendable (_ url: URL) async -> Bool
    ) async -> [RecommendedBook] {
    // 정보나루 표지를 먼저 찾고, 모자라면 4libs 링크를 실제로 받아 봐서 이미지인 것만 채운다.
    // 확인 함수를 밖에서 받는 이유: 테스트에서 호출 횟수를 셀 수 있게.
        guard limit > 0 else { return [] }
        var result = await firstCovers(in: candidates.filter { $0.isbn13 != nil }, limit: limit) { candidate in
            await data4LibraryLookup(candidate.isbn13!)
        }
        // 1단계: ISBN이 있는 책을 정보나루에 10권씩 물어본다. limit권이 모이면 멈춘다.
        guard result.count < limit else { return result }

        let chosen = Set(result.map(\.recordID))
        let fallback = candidates.filter { $0.primoCoverURL != nil && !chosen.contains($0.recordID) }
        // 2단계 대상: 아직 고르지 않았고 4libs 링크가 있는 책.
        result += await firstCovers(in: fallback, limit: limit - result.count) { candidate in
            guard let url = candidate.primoCoverURL else { return nil }
            return await isRealImage(url) ? url : nil
        }
        // 4libs는 표지가 없어도 링크가 있으므로, 실제로 받아 본 결과가 이미지일 때만 통과.
        return result
    }

    private static func firstCovers(
        in candidates: [ColdStartCandidate],
        limit: Int,
        check: @escaping @Sendable (ColdStartCandidate) async -> URL?
    ) async -> [RecommendedBook] {
    // 후보를 앞에서부터 10권씩 동시에 확인하고, limit권이 모이면 멈춘다.
        var result: [RecommendedBook] = []
        var start = 0
        while start < candidates.count, result.count < limit {
            let end = min(start + ColdStartRecommendation.coverBatchSize, candidates.count)
            let batch = Array(candidates[start..<end])
            let coverByIndex = await withTaskGroup(of: (Int, URL?).self) { group in
                for (index, candidate) in batch.enumerated() {
                    group.addTask { (index, await check(candidate)) }
                }
                var found: [Int: URL] = [:]
                for await (index, url) in group {
                    if let url { found[index] = url }
                }
                return found
            }
            result += batch.indices.compactMap { index in
                coverByIndex[index].map { RecommendedBook(recordID: batch[index].recordID, coverImageURL: $0) }
            }
            // 응답이 온 순서가 아니라 섞인 후보 순서를 유지한다.
            start = end
        }
        return Array(result.prefix(limit))
    }

    private static func isRealImage(_ url: URL) async -> Bool {
    // 주소를 실제로 받아 보고 이미지인지 확인한다.
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
            http.mimeType?.hasPrefix("image/") == true
        else { return false }
        return data.count >= ColdStartRecommendation.minimumCoverBytes
        // 표지가 없으면 4libs는 빈 HTML(0바이트)을 준다.
    }

    // MARK: - 포스텍 Primo

    private static func searchPrimo(query: String, offset: Int, apiKey: String) async throws -> Data {
    // 포스텍 도서관 Primo 검색 API를 한 번 호출하고 응답 원본을 돌려준다.
        var components = URLComponents(string: "https://api-ap.hosted.exlibrisgroup.com/primo/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "vid", value: "82POSTECH_INST:82POSTECH"),
            URLQueryItem(name: "tab", value: "LibraryCatalog"),
            URLQueryItem(name: "scope", value: "MyInstitution"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "multiFacets", value: "facet_rtype,include,printed_book"),
            // 조건: 전자자료가 아닌 인쇄도서만.
            URLQueryItem(name: "lang", value: "ko"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(ColdStartRecommendation.primoFetchCount)),
            URLQueryItem(name: "skipDelivery", value: "false")
            // 청구기호와 표지 링크(delivery)까지 받으려면 false여야 한다.
        ]
        guard let url = components?.url else { throw ColdStartRecommendationError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ColdStartRecommendationError.invalidResponse
        }
        return data
    }

    static func parsePrimo(_ data: Data, codes: [String]) throws -> PrimoCandidatePage {
    // 포스텍 응답을 해석해 조건을 통과한 후보만 남긴다.
        let response = try JSONDecoder().decode(PrimoResponse.self, from: data)
        var seen = Set<String>()
        let candidates = response.docs.compactMap { doc -> ColdStartCandidate? in
            guard let recordID = doc.pnx.control.recordid.first, !recordID.isEmpty,
                  seen.insert(recordID).inserted else { return nil }
            // recordid가 없거나 이미 담은 책이면 탈락.
            let callNumbers = doc.delivery?.holding?.compactMap(\.callNumber) ?? []
            guard callNumbers.contains(where: {
                ColdStartRecommendation.callNumber($0, matchesAnyOf: codes)
            }) else { return nil }
            // 조건: 청구기호가 있고, 관심 분류(하위 분류 포함)로 시작해야 한다.
            let primoCoverURL = primoThumbnailURL(from: doc.delivery?.link)
            let isbn13 = BookISBN.isbn13(from: doc.pnx.addata?.isbn?.joined(separator: " "))
            guard primoCoverURL != nil || isbn13 != nil else { return nil }
            // 포스텍 표지도 ISBN도 없으면 표지를 구할 방법이 없으므로 탈락.
            return ColdStartCandidate(recordID: recordID, primoCoverURL: primoCoverURL, isbn13: isbn13)
        }
        return PrimoCandidatePage(total: response.info.total, candidates: candidates)
    }

    private static func primoThumbnailURL(from links: [PrimoLink]?) -> URL? {
    // 포스텍 응답의 링크 목록에서 표지 이미지 주소를 찾는다. BookClient와 같은 기준이다.
        links?
            .filter { $0.linkType == "thumbnail" || $0.linkType?.hasSuffix("/thumbnail") == true }
            .compactMap { link -> URL? in
                guard
                    let address = link.linkURL,
                    let parts = URLComponents(string: address)
                        ?? address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                            .flatMap(URLComponents.init(string:)),
                    // 4libs 링크는 "isbn=978… (pbk. : alk. paper)"처럼 공백이 섞여 와서 그대로는 주소가 안 된다.
                    parts.scheme?.lowercased() == "https",
                    let host = parts.host, !host.isEmpty
                else { return nil }
                let isLookup = parts.queryItems?.contains {
                    $0.name == "jscmd" && $0.value == "viewapi"
                } ?? false
                // jscmd=viewapi는 이미지가 아니라 정보를 돌려주는 조회용 주소다.
                return isLookup ? nil : parts.url
            }
            .first
    }

    // MARK: - 정보나루 표지

    private static func data4LibraryCoverURL(isbn13: String, apiKey: String) async throws -> URL? {
    // ISBN 하나로 정보나루 도서 상세를 조회해 표지 주소를 꺼낸다.
        var components = URLComponents(string: "https://data4library.kr/api/srchDtlList")
        components?.queryItems = [
            URLQueryItem(name: "authKey", value: apiKey),
            URLQueryItem(name: "isbn13", value: isbn13),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw ColdStartRecommendationError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ColdStartRecommendationError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(Data4LibraryDetailResponse.self, from: data)
        guard let raw = decoded.response.detail?.first?.book.bookImageURL else { return nil }
        return secureCoverURL(raw)
    }

    static func secureCoverURL(_ raw: String) -> URL? {
    // 정보나루 표지 주소를 https로 맞춘다.
    // 앱에 http 예외(ATS)가 없어서 http 이미지는 화면에 뜨지 않는다. 알라딘은 https로도 같은 이미지를 준다.
        guard var parts = URLComponents(string: raw), parts.host?.isEmpty == false else { return nil }
        switch parts.scheme?.lowercased() {
        case "https": break
        case "http": parts.scheme = "https"
        default: return nil
        }
        return parts.url
    }

    // MARK: - 응답 모양

    private nonisolated struct PrimoResponse: Decodable {
        let info: PrimoInfo
        let docs: [PrimoDocument]
    }

    private nonisolated struct PrimoInfo: Decodable {
        let total: Int
    }

    private nonisolated struct PrimoDocument: Decodable {
        let pnx: PrimoPNX
        let delivery: PrimoDelivery?
    }

    private nonisolated struct PrimoPNX: Decodable {
        let control: PrimoControl
        let addata: PrimoAddData?
    }

    private nonisolated struct PrimoControl: Decodable {
        let recordid: [String]
    }

    private nonisolated struct PrimoAddData: Decodable {
        let isbn: [String]?
    }

    private nonisolated struct PrimoDelivery: Decodable {
        let holding: [PrimoHolding]?
        let link: [PrimoLink]?
    }

    private nonisolated struct PrimoHolding: Decodable {
        let callNumber: String?
    }

    private nonisolated struct PrimoLink: Decodable {
        let linkType: String?
        let linkURL: String?
    }

    private nonisolated struct Data4LibraryDetailResponse: Decodable {
        let response: Body
        nonisolated struct Body: Decodable {
            let detail: [Detail]?
        }
        nonisolated struct Detail: Decodable {
            let book: Book
        }
        nonisolated struct Book: Decodable {
            let bookImageURL: String?
        }
    }
}
