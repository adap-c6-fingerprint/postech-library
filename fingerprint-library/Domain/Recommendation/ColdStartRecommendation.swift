//
//  ColdStartRecommendation.swift
//  fingerprint-library
//

import Foundation
// Domain 폴더 규칙: SwiftUI·MapKit·TCA를 쓰지 않고 Foundation만 쓴다.

nonisolated struct RecommendedBook: Equatable, Identifiable, Sendable {
// 최종 출력값. 홈 화면에 보여 줄 추천 도서 한 권.
    let recordID: String
    // 포스텍 Primo 레코드 ID. 예: "alma991003561179303286"
    let coverImageURL: URL
    // 표지 이미지 주소. 포스텍 응답 또는 정보나루에서 얻는다.

    var id: String { recordID }
    // SwiftUI 목록에서 한 줄씩 구별할 때 recordID를 쓴다.
}

nonisolated struct ColdStartCandidate: Equatable, Sendable {
// 표지 검사 전 후보 도서.
    let recordID: String
    let primoCoverURL: URL?
    // 포스텍 응답의 표지 링크(4libs). 표지가 없어도 링크가 붙어 있어서, 실제로 받아 봐야 알 수 있다.
    let isbn13: String?
    // 정보나루에서 표지를 찾기 위한 ISBN13. 정보나루를 먼저 확인한다.
    // 둘 중 하나는 반드시 있다 (둘 다 없는 책은 후보가 되지 못한다).
}

nonisolated enum ColdStartRecommendation {
// 찜·검색 기록이 없는 사용자를 위한 첫 추천 규칙 모음.

    static let primoFetchCount = 50
    // 포스텍 API에 한 번에 요청하는 책 수.
    static let resultCount = 6
    // 홈 화면에 최종으로 보여 줄 책 수.
    static let coverBatchSize = 10
    // 표지를 한 번에 동시에 확인할 책 수. 6권이 모이면 다음 묶음은 보내지 않는다.
    static let extraPageLimit = 1
    // 표지 있는 책이 6권보다 적을 때 다른 무작위 위치에서 더 받아 올 최대 횟수.
    static let minimumCoverBytes = 1_000
    // 4libs는 표지가 없으면 빈 응답(0바이트)을 준다. 실제 표지는 2~4KB였다 (2026-10-28 확인).
    static let primoGuestWindow = 500
    // 게스트 키 제한: offset + limit이 500을 넘으면 401 오류가 난다.
    static let placeholderInterests = ["A", "P", "Q"]
    // 온보딩 전 임시 관심사. UserProfile.placeholderInterests와 같은 값이다.
    // TODO: #76(UserProfile)이 합쳐지면 이 상수를 지우고 UserProfile.interests를 쓴다.

    static func shouldApply(favoriteKeys: Set<[String?]>, recentQueries: [String]) -> Bool {
    // 이 추천을 쓸지 판단한다.
        favoriteKeys.isEmpty && recentQueries.isEmpty
        // 찜 목록과 최근 검색이 둘 다 비어 있을 때만 true.
    }

    static func normalizedCodes(_ interests: [String]) -> [String] {
    // 관심사 문자열을 LCC 분류기호 형태로 정리한다.
        var codes: [String] = []
        for interest in interests {
            let code = interest.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // 공백을 지우고 대문자로 바꾼다. 예: " qc " → "QC"
            let isLCC = !code.isEmpty && code.count <= 3
                && code.allSatisfy { $0.isASCII && $0.isLetter }
            // LCC 분류기호는 영문 1~3자리다. 예: "Q", "QC", "DJK"
            guard isLCC, !codes.contains(code) else { continue }
            // 형식이 아니거나 이미 담은 값이면 건너뛴다.
            codes.append(code)
        }
        return codes
    }

    static func primoQuery(for codes: [String]) -> String {
    // 포스텍 API의 q 값을 만든다.
        let classes = codes.flatMap(LCCOutline.expand)
        // 관심 분류를 하위 분류까지 펼친다. 예: ["Q"] → ["Q", "QA", "QB", …]
        let terms = classes.flatMap { code in (1...9).map { "\(code)\($0)*" } }
        // 분류기호마다 뒤에 숫자 1~9를 붙인 와일드카드를 만든다. 예: "QC" → "QC1*" … "QC9*"
        // 숫자를 붙이는 이유: "QC*"만 쓰면 "QCD" 같은 일반 단어도 걸리기 때문.
        return "any,contains," + terms.joined(separator: " OR ")
    }

    static func callNumber(_ callNumber: String, matchesAnyOf codes: [String]) -> Bool {
    // 청구기호가 관심 분류 중 하나에 속하는지 확인한다.
        let text = callNumber.trimmingCharacters(in: .whitespaces).uppercased()
        // 예: "QC174.12 .M47 1998"
        let letters = String(text.prefix { $0.isASCII && $0.isLetter })
        // 앞쪽 영문자만 떼어 낸다. 예: "QC174.12 …" → "QC"
        guard (1...3).contains(letters.count) else { return false }
        // LCC 분류기호는 1~3글자. 아니면 LCC 청구기호가 아니다.
        let rest = text.dropFirst(letters.count).drop(while: { $0 == " " })
        // 분류기호 뒷부분. 사이에 공백이 있어도 건너뛴다.
        guard rest.first?.isNumber == true else { return false }
        // 분류기호 바로 뒤가 숫자여야 진짜 청구기호다.
        return codes.contains { letters.hasPrefix($0) }
        // 관심사 "Q" → "Q180", "QA76", "QC174" 모두 통과 / 관심사 "QC" → "QA76" 탈락
    }

    static func randomOffset<G: RandomNumberGenerator>(total: Int, using generator: inout G) -> Int {
    // 검색 결과 중 어디서부터 받을지 무작위로 고른다.
        let window = min(total, primoGuestWindow)
        // 실제로 접근할 수 있는 범위. 전체가 9,000권이어도 500까지만 볼 수 있다.
        let maxOffset = window - primoFetchCount
        // 50권을 받아도 범위를 넘지 않는 가장 큰 시작 위치.
        guard maxOffset > 0 else { return 0 }
        // 결과가 50권 이하라 고를 여지가 없으면 처음부터.
        return Int.random(in: 0...maxOffset, using: &generator)
    }
}
