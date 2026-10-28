//
//  PersonalizedRecommendation.swift
//  fingerprint-library
//

import Foundation
// Domain 폴더 규칙: SwiftUI·MapKit·TCA를 쓰지 않고 Foundation만 쓴다.

nonisolated struct PersonalizedCandidate: Equatable, Sendable {
// 키워드 검색으로 받은 후보 도서. 모델 정렬과 표지 확인에 쓴다.
    let recordID: String
    let title: String
    let subject: String?
    // 첫 번째 주제어. 모델이 관련도를 판단할 때 제목과 함께 본다.
    let callNumber: String
    let primoCoverURL: URL?
    let isbn13: String?
}

nonisolated struct PersonalizedRecommendationInput: Equatable, Sendable {
// 추천에 필요한 사용자 데이터 묶음.
    let favoriteKeys: Set<[String?]>
    let recentQueries: [String]
    let interests: [String]
}

nonisolated enum PersonalizedRecommendation {
// 찜·검색 기록이 있는 사용자를 위한 추천 규칙 모음.

    static let keywordCount = 5
    // 모델이 뽑을 관심사 키워드 수.
    static let primoFetchCount = 50
    // 키워드 검색으로 받아 올 책 수.
    static let favoriteLookupLimit = 20
    // 제목을 조회할 찜 도서 최대 수. 모델 입력이 너무 길어지지 않게 자른다.
    static let recentQueryLimit = 10
    // 모델에 넘길 최근 검색어 최대 수.
    static let promptTitleLength = 40
    // 모델 입력에 넣을 제목 최대 글자 수. 50권을 한 번에 넣어도 모델 입력 한도를 넘지 않게 한다.

    static func shouldApply(favoriteKeys: Set<[String?]>, recentQueries: [String]) -> Bool {
    // 이 추천을 쓸지 판단한다.
        !ColdStartRecommendation.shouldApply(favoriteKeys: favoriteKeys, recentQueries: recentQueries)
        // 찜이나 최근 검색 중 하나라도 있으면 true. 둘 다 비면 첫 추천(ColdStart)을 쓴다.
    }

    // MARK: - 찜 목록 해석

    static func favoriteMMSIDs(_ keys: Set<[String?]>) -> [String] {
    // 찜 키에서 포스텍 레코드 번호를 꺼낸다.
    // 예: ["control", "primo:alma991003618878303286"] → "991003618878303286"
    // Primo는 "alma"를 뗀 숫자로 검색해야 찾아진다 (2026-10-28 확인).
        let ids = keys.compactMap { key -> String? in
            guard key.count == 2, key[0] == "control", let value = key[1] else { return nil }
            let digits = value.replacingOccurrences(of: "primo:", with: "")
                .replacingOccurrences(of: "alma", with: "")
            return !digits.isEmpty && digits.allSatisfy(\.isNumber) ? digits : nil
        }
        return Array(ids.sorted().prefix(favoriteLookupLimit))
        // Set은 순서가 없어서 정렬해 매번 같은 결과가 나오게 한다.
    }

    static func favoriteMetadataTitles(_ keys: Set<[String?]>) -> [String] {
    // 레코드 번호 없이 저장된 찜(metadata 키)은 제목을 바로 꺼낸다.
    // 예: ["metadata", isbn, "스위프트 입문", 저자, 출판사, 연도] → "스위프트 입문"
        keys.compactMap { key -> String? in
            guard key.count > 2, key[0] == "metadata", let title = key[2] else { return nil }
            return title
        }
        .sorted()
    }

    static func primoRecordQuery(_ mmsIDs: [String]) -> String {
    // 찜 도서 제목을 한 번에 조회하는 q 값.
        "any,contains," + mmsIDs.joined(separator: " OR ")
    }

    // MARK: - 키워드

    static func normalizedKeywords(_ raw: [String]) -> [String] {
    // 모델이 만든 키워드를 검색어로 쓸 수 있게 정리한다.
        let reserved: Set<String> = ["OR", "AND", "NOT"]
        // Primo 검색 연산자. 키워드로 들어가면 검색식이 깨진다.
        var keywords: [String] = []
        for value in raw {
            let cleaned = value
                .components(separatedBy: CharacterSet(charactersIn: ",\"()*?:[]{}#"))
                .joined(separator: " ")
                // q 값의 구분자(,)와 검색 특수문자를 공백으로 바꾼다.
                .split(whereSeparator: \.isWhitespace)
                .filter { !reserved.contains($0.uppercased()) }
                .joined(separator: " ")
            // 공백을 한 칸으로 줄인다. 예: " 양자  역학 " → "양자 역학"
            guard !cleaned.isEmpty,
                  !keywords.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
            else { continue }
            keywords.append(cleaned)
            if keywords.count == keywordCount { break }
        }
        return keywords
    }

    static func fallbackKeywords(favoriteTitles: [String], recentQueries: [String]) -> [String] {
    // 모델을 쓸 수 없을 때(기기 미지원·Apple Intelligence 꺼짐 등) 쓰는 키워드.
        normalizedKeywords(recentQueries + favoriteTitles.map { String($0.prefix(promptTitleLength)) })
        // 최근 검색어를 먼저, 모자라면 찜한 책 제목으로 채운다.
    }

    static func primoKeywordQuery(_ keywords: [String]) -> String {
    // 키워드를 OR로 묶은 q 값. 예: "any,contains,반도체 OR 양자역학"
        "any,contains," + keywords.joined(separator: " OR ")
    }

    // MARK: - 모델 입력

    static let keywordInstructions = """
    너는 대학 도서관 사서다. 사용자가 찜한 책과 최근 검색어를 보고 사용자의 관심 주제를 파악한다.
    도서관 검색창에 넣을 키워드를 정확히 \(keywordCount)개 만든다.
    각 키워드는 한두 단어로 된 주제 명사다. 책 제목을 그대로 옮기지 않는다.
    """

    static func keywordPrompt(favoriteTitles: [String], recentQueries: [String]) -> String {
    // 키워드 추출에 넘길 사용자 데이터 문장.
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
    // 관련도 정렬에 넘길 책 목록. 번호는 1부터 시작한다.
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

    // MARK: - 정렬

    static func mergedRanking(modelOrder: [Int], count: Int) -> [Int] {
    // 모델이 준 번호(1부터)를 0부터 시작하는 순서로 바꾸고, 빠진 책은 원래 순서대로 뒤에 붙인다.
    // 모델은 범위 밖 번호나 같은 번호를 두 번 줄 수 있어서 그대로 믿지 않는다.
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
    // 모델 순서를 따르되, 관심 분류(UserProfile.interests)에 속한 책을 앞으로 모은다.
    // 모델이 [관심분류] 지시를 놓쳐도 이 단계에서 항상 지켜진다.
        let ordered = ranking.map { candidates[$0] }
        let matches = { (candidate: PersonalizedCandidate) in
            ColdStartRecommendation.callNumber(candidate.callNumber, matchesAnyOf: interestCodes)
        }
        return ordered.filter(matches) + ordered.filter { !matches($0) }
        // 두 묶음 안에서는 모델 순서가 유지된다.
    }
}
