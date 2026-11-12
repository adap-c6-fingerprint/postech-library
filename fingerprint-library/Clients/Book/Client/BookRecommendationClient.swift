import Foundation
import ComposableArchitecture

nonisolated struct BookRecommendationClient: Sendable {
    var fetch: @Sendable (_ count: Int) async throws -> [Book]
}

extension BookRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { count in
        guard count > 0 else { return [] }

        let (input, coldStart, personalized, bookClient) = await MainActor.run {
            @Shared(.favoriteBookKeys) var favoriteBookKeys
            @Dependency(\.searchHistoryClient) var history
            @Dependency(\.coldStartRecommendationClient) var coldStart
            @Dependency(\.personalizedRecommendationClient) var personalized
            @Dependency(\.bookClient) var bookClient
            @Shared(.userProfile) var userProfile: UserProfile?
            let input = PersonalizedRecommendationInput(
                favoriteKeys: favoriteBookKeys,
                recentQueries: history.load(),
                interests: userProfile?.interests ?? []
            )
            return (input, coldStart, personalized, bookClient)
        }
        try Task.checkCancellation()
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

        let recordNumbers = selected.map { recommendation in
            let id = recommendation.recordID
            return id.hasPrefix("alma") ? String(id.dropFirst(4)) : id
        }
        guard recordNumbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw URLError(.cannotParseResponse)
        }
        let metadata = try await bookClient.search(BookSearchRequest(
            query: recordNumbers.joined(separator: " OR "), category: .monograph
        ))
        try Task.checkCancellation()

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

nonisolated extension DependencyValues {
    var bookRecommendationClient: BookRecommendationClient {
        get { self[BookRecommendationClient.self] }
        set { self[BookRecommendationClient.self] = newValue }
    }
}
