//
//  PersonalizedRecommendationClient.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

nonisolated struct PersonalizedRecommendationClient: Sendable {
// 찜·검색 기록 기반 추천 도서를 가져오는 창구.
    var fetch: @Sendable (_ input: PersonalizedRecommendationInput) async throws -> [RecommendedBook]
    // 사용자 데이터를 넣으면 추천 도서(최대 6권)를 돌려준다.
}

extension PersonalizedRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { input in
        guard let primoKey = await AppConfiguration.primoAPIKey else {
            throw ColdStartRecommendationError.missingPrimoAPIKey
        }
        guard let data4LibraryKey = await AppConfiguration.data4LibraryAPIKey else {
            throw ColdStartRecommendationError.missingData4LibraryAPIKey
        }
        @Dependency(\.foundationModelsClient) var model
        return try await PersonalizedRecommendationService.recommend(
            input,
            dependencies: .init(
                model: model,
                searchPrimo: { query, limit in
                    try await PersonalizedRecommendationService.searchPrimo(query: query, limit: limit, apiKey: primoKey)
                },
                data4LibraryLookup: { isbn13 in
                    try? await ColdStartRecommendationService.data4LibraryCoverURL(isbn13: isbn13, apiKey: data4LibraryKey)
                },
                isRealImage: ColdStartRecommendationService.isRealImage
            )
        )
    })
    // 실제 앱: 기기 내 모델, 포스텍 API, 정보나루 API를 쓴다.
    static let testValue = Self(fetch: { _ in [] })
    // 테스트: 항상 빈 결과.
}

extension DependencyValues {
    var personalizedRecommendationClient: PersonalizedRecommendationClient {
        get { self[PersonalizedRecommendationClient.self] }
        set { self[PersonalizedRecommendationClient.self] = newValue }
    }
}

nonisolated enum PersonalizedRecommendationError: Error, Equatable {
    case noKeywords
    // 찜·검색 기록에서 검색 키워드를 하나도 만들지 못함.
}

nonisolated enum PersonalizedRecommendationService {

    nonisolated struct Dependencies: Sendable {
    // 바깥 시스템 호출 묶음. 테스트에서 가짜로 바꿔 끼운다.
        var model: FoundationModelsClient
        var searchPrimo: @Sendable (_ query: String, _ limit: Int) async throws -> Data
        var data4LibraryLookup: @Sendable (_ isbn13: String) async -> URL?
        var isRealImage: @Sendable (_ url: URL) async -> Bool
    }

    static func recommend(
        _ input: PersonalizedRecommendationInput,
        dependencies: Dependencies
    ) async throws -> [RecommendedBook] {
    // 전체 흐름을 실행한다.
        let mmsIDs = PersonalizedRecommendation.favoriteMMSIDs(input.favoriteKeys)
        var favoriteTitles = PersonalizedRecommendation.favoriteMetadataTitles(input.favoriteKeys)
        if !mmsIDs.isEmpty {
            let data = try? await dependencies.searchPrimo(
                PersonalizedRecommendation.primoRecordQuery(mmsIDs), mmsIDs.count
            )
            favoriteTitles += data.flatMap { try? parseTitles($0) } ?? []
        }
        // ① 찜 목록은 책 ID만 저장돼 있어서, 포스텍 API로 제목을 한 번에 조회한다.
        // 조회에 실패해도 최근 검색어만으로 계속 진행한다.

        let keywords = await keywords(
            favoriteTitles: favoriteTitles,
            recentQueries: input.recentQueries,
            model: dependencies.model
        )
        guard !keywords.isEmpty else { throw PersonalizedRecommendationError.noKeywords }
        // ② 모델이 관심사 키워드 5개를 뽑는다.

        let candidates = try parseCandidates(
            try await dependencies.searchPrimo(
                PersonalizedRecommendation.primoKeywordQuery(keywords),
                PersonalizedRecommendation.primoFetchCount
            )
        )
        // ③ 키워드를 OR로 묶어 포스텍에서 50권을 받는다.

        let interestCodes = ColdStartRecommendation.normalizedCodes(input.interests)
        let modelOrder = await ranking(
            candidates,
            keywords: keywords,
            interestCodes: interestCodes,
            model: dependencies.model
        )
        let ranked = PersonalizedRecommendation.prioritized(
            candidates,
            ranking: PersonalizedRecommendation.mergedRanking(modelOrder: modelOrder, count: candidates.count),
            interestCodes: interestCodes
        )
        // ④ 모델이 관련도 순으로 정렬하고, 관심 분류에 속한 책을 앞으로 모은다.

        return await topBooksWithCovers(
            ranked,
            data4LibraryLookup: dependencies.data4LibraryLookup,
            isRealImage: dependencies.isRealImage
        )
        // ⑤ 우선순위 순서대로 표지를 확인해 표지 있는 상위 6권을 돌려준다.
    }

    // MARK: - 모델 호출

    private static func keywords(
        favoriteTitles: [String],
        recentQueries: [String],
        model: FoundationModelsClient
    ) async -> [String] {
    // 모델로 키워드를 뽑는다. 모델을 못 쓰거나 실패하면 검색어·제목을 그대로 키워드로 쓴다.
        let fallback = PersonalizedRecommendation.fallbackKeywords(
            favoriteTitles: favoriteTitles,
            recentQueries: recentQueries
        )
        guard model.isAvailable() else { return fallback }
        let prompt = PersonalizedRecommendation.keywordPrompt(
            favoriteTitles: favoriteTitles,
            recentQueries: recentQueries
        )
        guard let raw = try? await model.extractKeywords(prompt) else { return fallback }
        let keywords = PersonalizedRecommendation.normalizedKeywords(raw)
        return keywords.isEmpty ? fallback : keywords
    }

    private static func ranking(
        _ candidates: [PersonalizedCandidate],
        keywords: [String],
        interestCodes: [String],
        model: FoundationModelsClient
    ) async -> [Int] {
    // 모델로 순서를 정한다. 모델을 못 쓰거나 실패하면 빈 배열 → 포스텍 검색 순서를 그대로 쓴다.
        guard model.isAvailable(), !candidates.isEmpty else { return [] }
        let prompt = PersonalizedRecommendation.rankingPrompt(
            candidates,
            keywords: keywords,
            interestCodes: interestCodes
        )
        return (try? await model.rankBooks(prompt)) ?? []
    }

    // MARK: - 표지 고르기

    static func topBooksWithCovers(
        _ ranked: [PersonalizedCandidate],
        limit: Int = ColdStartRecommendation.resultCount,
        data4LibraryLookup: @escaping @Sendable (_ isbn13: String) async -> URL?,
        isRealImage: @escaping @Sendable (_ url: URL) async -> Bool
    ) async -> [RecommendedBook] {
    // 우선순위 순서를 지키며 표지를 확인한다. 책마다 정보나루 → 4libs 순서로 시도한다.
    // 첫 추천과 다른 점: 정보나루 표지가 있는 책을 먼저 모으지 않는다. 순위가 높은 책이 표지 출처 때문에 밀리지 않게.
        var result: [RecommendedBook] = []
        var start = 0
        while start < ranked.count, result.count < limit {
            let end = min(start + ColdStartRecommendation.coverBatchSize, ranked.count)
            let batch = Array(ranked[start..<end])
            let coverByIndex = await withTaskGroup(of: (Int, URL?).self) { group in
                for (index, candidate) in batch.enumerated() {
                    group.addTask {
                        if let isbn13 = candidate.isbn13, let url = await data4LibraryLookup(isbn13) {
                            return (index, url)
                        }
                        if let url = candidate.primoCoverURL, await isRealImage(url) {
                            return (index, url)
                        }
                        return (index, nil)
                    }
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
            // 응답이 온 순서가 아니라 우선순위 순서를 유지한다.
            start = end
        }
        return Array(result.prefix(limit))
    }

    // MARK: - 포스텍 Primo

    static func searchPrimo(query: String, limit: Int, apiKey: String) async throws -> Data {
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
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: String(limit)),
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

    static func parseTitles(_ data: Data) throws -> [String] {
    // 찜 도서 조회 응답에서 제목만 꺼낸다.
        try JSONDecoder().decode(PrimoResponse.self, from: data).docs.compactMap { doc in
            doc.pnx.display.title?.first.map(BookText.plainText).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    static func parseCandidates(_ data: Data) throws -> [PersonalizedCandidate] {
    // 키워드 검색 응답을 해석해 조건을 통과한 후보만 남긴다. 조건은 첫 추천과 같다.
        let response = try JSONDecoder().decode(PrimoResponse.self, from: data)
        var seen = Set<String>()
        return response.docs.compactMap { doc -> PersonalizedCandidate? in
            guard let recordID = doc.pnx.control.recordid.first, !recordID.isEmpty,
                  seen.insert(recordID).inserted else { return nil }
            // recordid가 없거나 이미 담은 책이면 탈락.
            guard let title = doc.pnx.display.title?.first.map(BookText.plainText), !title.isEmpty else {
                return nil
            }
            // 모델이 판단할 제목이 없으면 탈락.
            guard let callNumber = doc.delivery?.holding?
                .compactMap({ $0.callNumber?.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty })
            else { return nil }
            // 조건: 청구기호가 있어야 한다.
            let primoCoverURL = ColdStartRecommendationService.primoThumbnailURL(from: doc.delivery?.link)
            let isbn13 = BookISBN.isbn13(from: doc.pnx.addata?.isbn?.joined(separator: " "))
            guard primoCoverURL != nil || isbn13 != nil else { return nil }
            // 포스텍 표지도 ISBN도 없으면 표지를 구할 방법이 없으므로 탈락.
            return PersonalizedCandidate(
                recordID: recordID,
                title: title,
                subject: doc.pnx.display.subject?.first.map(BookText.plainText),
                callNumber: callNumber,
                primoCoverURL: primoCoverURL,
                isbn13: isbn13
            )
        }
    }

    // MARK: - 응답 모양

    private nonisolated struct PrimoResponse: Decodable {
        let docs: [PrimoDocument]
    }

    private nonisolated struct PrimoDocument: Decodable {
        let pnx: PrimoPNX
        let delivery: PrimoDelivery?
    }

    private nonisolated struct PrimoPNX: Decodable {
        let control: PrimoControl
        let display: PrimoDisplay
        let addata: PrimoAddData?
    }

    private nonisolated struct PrimoControl: Decodable {
        let recordid: [String]
    }

    private nonisolated struct PrimoDisplay: Decodable {
        let title: [String]?
        let subject: [String]?
    }

    private nonisolated struct PrimoAddData: Decodable {
        let isbn: [String]?
    }

    private nonisolated struct PrimoDelivery: Decodable {
        let holding: [PrimoHolding]?
        let link: [ColdStartRecommendationService.PrimoLink]?
    }

    private nonisolated struct PrimoHolding: Decodable {
        let callNumber: String?
    }
}
