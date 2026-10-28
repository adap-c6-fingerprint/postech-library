import Foundation
import ComposableArchitecture

struct BookRecommendationClient: Sendable {
    var fetch: @Sendable (_ count: Int) async throws -> [Book]
}

extension BookRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { count in
        guard count > 0 else { return [] }

        let (input, coldStart, personalized, bookClient) = await MainActor.run {
            @Dependency(\.bookFavoritesClient) var favorites
            @Dependency(\.searchHistoryClient) var history
            @Dependency(\.coldStartRecommendationClient) var coldStart
            @Dependency(\.personalizedRecommendationClient) var personalized
            @Dependency(\.bookClient) var bookClient
            let input = PersonalizedRecommendationInput(
                favoriteKeys: favorites.load(),
                recentQueries: history.load(),
                interests: ColdStartRecommendation.placeholderInterests
            )
            return (input, coldStart, personalized, bookClient)
        }
        try Task.checkCancellation()
        // 온보딩의 관심사 저장이 연결되면 placeholderInterests를 교체한다.
        let recommendations: [RecommendedBook]
        if PersonalizedRecommendation.shouldApply(
            favoriteKeys: input.favoriteKeys, recentQueries: input.recentQueries
        ) {
            let personalizedBooks: [RecommendedBook]
            do {
                personalizedBooks = try await personalized.fetch(input)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                personalizedBooks = []
            }
            try Task.checkCancellation()
            recommendations = personalizedBooks.isEmpty
                ? try await coldStart.fetch(input.interests)
                : personalizedBooks
        } else {
            recommendations = try await coldStart.fetch(input.interests)
        }
        try Task.checkCancellation()

        var seen = Set<String>()
        let selected = Array(recommendations.filter {
            seen.insert($0.recordID).inserted
        }.prefix(min(count, ColdStartRecommendation.resultCount)))
        guard !selected.isEmpty else { return [] }

        // 추천 결과에는 ID·검증한 표지만 있으므로 기존 BookClient로 메타데이터를 보완한다.
        // BookClient.search가 any,contains를 붙인다. 여기에는 숫자 레코드 번호만 전달한다.
        let recordNumbers = selected.map { recommendation in
            let id = recommendation.recordID
            return id.hasPrefix("alma") ? String(id.dropFirst(4)) : id
        }
        guard recordNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw URLError(.cannotParseResponse)
        }
        let metadata = try await bookClient.search(recordNumbers.joined(separator: " OR "))
        try Task.checkCancellation()

        // 검색 응답의 순서·표지 대신 알고리즘의 추천 순서·확인된 표지를 유지한다.
        return selected.compactMap { recommendation in
            let identity = "primo:\(recommendation.recordID)"
            guard let book = metadata.first(where: {
                $0.id == identity || $0.controlNumber == identity
            }) else { return nil }
            return Book(
                id: book.id, isbn: book.isbn, controlNumber: book.controlNumber,
                title: book.title, author: book.author, publisher: book.publisher,
                publicationYear: book.publicationYear, description: book.description,
                imageURL: recommendation.coverImageURL
            )
        }
    })

    static let testValue = Self(fetch: { _ in [] })
}

extension DependencyValues {
    var bookRecommendationClient: BookRecommendationClient {
        get { self[BookRecommendationClient.self] }
        set { self[BookRecommendationClient.self] = newValue }
    }
}
