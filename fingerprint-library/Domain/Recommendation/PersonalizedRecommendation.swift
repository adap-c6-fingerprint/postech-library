//
//  PersonalizedRecommendation.swift
//  fingerprint-library
//

import Foundation

nonisolated struct PersonalizedCandidate: Equatable, Sendable {
    let recordID: String
    let title: String
    let subject: String?
    let callNumber: String
    let primoCoverURL: URL?
    let isbn13: String?
}

nonisolated struct PersonalizedRecommendationInput: Equatable, Sendable {
    let favoriteKeys: Set<[String?]>
    let recentQueries: [String]
    let interests: [String]
}

nonisolated enum PersonalizedRecommendation {
    static let keywordCount = 5
    static let primoFetchCount = 50
    static let favoriteLookupLimit = 20
    static let recentQueryLimit = 10
    static let promptTitleLength = 40

    static func shouldApply(favoriteKeys: Set<[String?]>, recentQueries: [String]) -> Bool {
        !ColdStartRecommendation.shouldApply(favoriteKeys: favoriteKeys, recentQueries: recentQueries)
    }

    static func favoriteMMSIDs(_ keys: Set<[String?]>) -> [String] {
        let ids = keys.compactMap { key -> String? in
            guard key.count == 2, key[0] == "control", let value = key[1] else { return nil }
            let digits = value.replacingOccurrences(of: "primo:", with: "")
                .replacingOccurrences(of: "alma", with: "")
            return !digits.isEmpty && digits.allSatisfy(\.isNumber) ? digits : nil
        }
        return Array(ids.sorted().prefix(favoriteLookupLimit))
    }

    static func favoriteMetadataTitles(_ keys: Set<[String?]>) -> [String] {
        keys.compactMap { key -> String? in
            guard key.count > 2, key[0] == "metadata", let title = key[2] else { return nil }
            return title
        }
        .sorted()
    }

    static func primoRecordQuery(_ mmsIDs: [String]) -> String {
        "any,contains," + mmsIDs.joined(separator: " OR ")
    }

    static func normalizedKeywords(_ raw: [String]) -> [String] {
        let reserved: Set<String> = ["OR", "AND", "NOT"]
        var keywords: [String] = []
        for value in raw {
            let cleaned = value
                .components(separatedBy: CharacterSet(charactersIn: ",\"()*?:[]{}#"))
                .joined(separator: " ")
                .split(whereSeparator: \.isWhitespace)
                .filter { !reserved.contains($0.uppercased()) }
                .joined(separator: " ")
            guard !cleaned.isEmpty,
                  !keywords.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
            else { continue }
            keywords.append(cleaned)
            if keywords.count == keywordCount { break }
        }
        return keywords
    }

    static func fallbackKeywords(favoriteTitles: [String], recentQueries: [String]) -> [String] {
        normalizedKeywords(recentQueries + favoriteTitles.map { String($0.prefix(promptTitleLength)) })
    }

    static func primoKeywordQuery(_ keywords: [String]) -> String {
        "any,contains," + keywords.joined(separator: " OR ")
    }

    static let keywordInstructions = """
    너는 대학 도서관 사서다. 사용자가 찜한 책과 최근 검색어를 보고 사용자의 관심 주제를 파악한다.
    도서관 검색창에 넣을 키워드를 정확히 \(keywordCount)개 만든다.
    각 키워드는 한두 단어로 된 주제 명사다. 책 제목을 그대로 옮기지 않는다.
    """

    static func keywordPrompt(favoriteTitles: [String], recentQueries: [String]) -> String {
        let titles = favoriteTitles.prefix(favoriteLookupLimit).map { "- \($0.prefix(promptTitleLength))" }
        let queries = recentQueries.prefix(recentQueryLimit).map { "- \($0)" }
        return """
        찜한 책:
        \(titles.isEmpty ? "- 없음" : titles.joined(separator: "\n"))
        최근 검색어:
        \(queries.isEmpty ? "- 없음" : queries.joined(separator: "\n"))
        """
    }

    static let rankingInstructions = """
    너는 대학 도서관 사서다. 사용자 관심 키워드와 책 목록을 보고, 사용자에게 추천할 순서대로 책 번호를 나열한다.
    키워드와 관련도가 높은 책이 앞에 온다. [관심분류] 표시가 있는 책은 사용자가 고른 관심 분류에 속하므로 우선한다.
    목록에 있는 번호만 쓴다.
    """

    static func rankingPrompt(
        _ candidates: [PersonalizedCandidate],
        keywords: [String],
        interestCodes: [String]
    ) -> String {
        let lines = candidates.enumerated().map { index, candidate in
            var line = "\(index + 1). \(candidate.title.prefix(promptTitleLength))"
            if let subject = candidate.subject { line += " (\(subject.prefix(20)))" }
            if ColdStartRecommendation.callNumber(candidate.callNumber, matchesAnyOf: interestCodes) {
                line += " [관심분류]"
            }
            return line
        }
        return """
        관심 키워드: \(keywords.joined(separator: ", "))
        책 목록:
        \(lines.joined(separator: "\n"))
        """
    }

    static func mergedRanking(modelOrder: [Int], count: Int) -> [Int] {
        var seen = Set<Int>()
        let ranked = modelOrder
            .map { $0 - 1 }
            .filter { (0..<count).contains($0) && seen.insert($0).inserted }
        return ranked + (0..<count).filter { !seen.contains($0) }
    }

    static func prioritized(
        _ candidates: [PersonalizedCandidate],
        ranking: [Int],
        interestCodes: [String]
    ) -> [PersonalizedCandidate] {
        let ordered = ranking.map { candidates[$0] }
        let matches = { (candidate: PersonalizedCandidate) in
            ColdStartRecommendation.callNumber(candidate.callNumber, matchesAnyOf: interestCodes)
        }
        return ordered.filter(matches) + ordered.filter { !matches($0) }
    }
}
