//
//  HeldRelatedBooksClient.swift
//  fingerprint-library
//
//  ✅ 이슈 #237 (Q2): 정보나루 연관도서 중 포스텍 도서관이 소장한 책만 돌려준다.
//  정보나루는 공공도서관 데이터라 포스텍에 없는 책이 섞이므로, Primo에서 ISBN으로 다시 찾아
//  소장이 확인된 책(primo: id)만 후보로 쓴다.
//

import ComposableArchitecture
import Foundation

nonisolated struct HeldRelatedBooksClient: Sendable {
    var candidates: @Sendable (_ source: Book, _ limit: Int) async -> [Book]

    static func live(related: RelatedBooksClient, bookClient: BookClient) -> Self {
        Self(candidates: { source, limit in
            guard limit > 0, let isbn = BookISBN.isbn13(from: source.isbn) else { return [] }
            let relatedBooks = (try? await related.fetch(isbn)) ?? []
            var held: [Book] = []
            for candidate in relatedBooks.prefix(limit * 3) {
                guard held.count < limit, !Task.isCancelled else { break }
                if let book = await heldBook(for: candidate, bookClient: bookClient) {
                    held.append(book)
                }
            }
            return held
        })
    }

    private static func heldBook(for candidate: Book, bookClient: BookClient) async -> Book? {
        guard let isbn = BookISBN.isbn13(from: candidate.isbn),
              let results = try? await bookClient.search(BookSearchRequest(query: isbn, category: .monograph))
        else { return nil }
        guard let match = results.first(where: {
            BookISBN.isbn13(from: $0.isbn) == isbn && BookHoldingsClient.recordID(for: $0) != nil
        }) else { return nil }
        guard match.imageURL == nil, let cover = candidate.imageURL else { return match }
        return Book(
            id: match.id, isbn: match.isbn, controlNumber: match.controlNumber, title: match.title,
            author: match.author, publisher: match.publisher, publicationYear: match.publicationYear,
            description: match.description, imageURL: cover, subLocation: match.subLocation
        )
    }
}

extension HeldRelatedBooksClient: DependencyKey {
    static let liveValue = Self.live(related: .liveValue, bookClient: .liveValue)

    static let testValue = Self(candidates: { _, _ in [] })
}

nonisolated extension DependencyValues {
    var heldRelatedBooksClient: HeldRelatedBooksClient {
        get { self[HeldRelatedBooksClient.self] }
        set { self[HeldRelatedBooksClient.self] = newValue }
    }
}

nonisolated enum RelatedRecommendationAssembler {
    static func assemble(
        sources: [Book], fallback: [Book], count: Int, related: HeldRelatedBooksClient,
        excluding excludedKeys: Set<String> = [], includesRemainingRelatedBooks: Bool = false
    ) async -> [Book] {
        let candidates = await withTaskGroup(of: (Int, [Book]).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, await related.candidates(source, 3)) }
            }
            var byIndex: [Int: [Book]] = [:]
            for await (index, books) in group { byIndex[index] = books }
            return sources.indices.map { byIndex[$0] ?? [] }
        }
        let remaining = includesRemainingRelatedBooks ? fallback + candidates.flatMap { $0 } : fallback
        return DatasetRecommendation.assemble(
            candidatesPerSource: candidates, fallback: remaining, count: count, excluding: excludedKeys
        )
    }
}
