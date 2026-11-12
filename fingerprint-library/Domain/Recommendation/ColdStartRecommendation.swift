//
//  ColdStartRecommendation.swift
//  fingerprint-library
//

import Foundation

nonisolated struct RecommendedBook: Equatable, Identifiable, Sendable {
    let recordID: String
    let coverImageURL: URL

    var id: String { recordID }
}

nonisolated struct ColdStartCandidate: Equatable, Sendable {
    let recordID: String
    let primoCoverURL: URL?
    let isbn13: String?
}

nonisolated enum ColdStartRecommendation {
    static let primoFetchCount = 50
    static let resultCount = 6
    static let coverBatchSize = 10
    static let extraPageLimit = 1
    static let minimumCoverBytes = 1_000
    static let primoGuestWindow = 500

    static func shouldApply(favoriteKeys: Set<[String?]>, recentQueries: [String]) -> Bool {
        favoriteKeys.isEmpty && recentQueries.isEmpty
    }

    static func normalizedCodes(_ interests: [String]) -> [String] {
        var codes: [String] = []
        for interest in interests {
            let code = interest.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isLCC = !code.isEmpty && code.count <= 3
                && code.allSatisfy { $0.isASCII && $0.isLetter }
            guard isLCC, !codes.contains(code) else { continue }
            codes.append(code)
        }
        return codes
    }

    static func primoQuery(for codes: [String]) -> String {
        let classes = codes.flatMap(LCCOutline.expand)
        let terms = classes.flatMap { code in (1...9).map { "\(code)\($0)*" } }
        return "any,contains," + terms.joined(separator: " OR ")
    }

    static func callNumber(_ callNumber: String, matchesAnyOf codes: [String]) -> Bool {
        let text = callNumber.trimmingCharacters(in: .whitespaces).uppercased()
        let letters = String(text.prefix { $0.isASCII && $0.isLetter })
        guard (1...3).contains(letters.count) else { return false }
        let rest = text.dropFirst(letters.count).drop(while: { $0 == " " })
        guard rest.first?.isNumber == true else { return false }
        return codes.contains { letters.hasPrefix($0) }
    }

    static func randomOffset<G: RandomNumberGenerator>(total: Int, using generator: inout G) -> Int {
        let window = min(total, primoGuestWindow)
        let maxOffset = window - primoFetchCount
        guard maxOffset > 0 else { return 0 }
        return Int.random(in: 0...maxOffset, using: &generator)
    }
}
