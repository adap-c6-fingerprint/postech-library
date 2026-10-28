import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookRecommendationClientTests {
    @Test("기록이 없으면 첫 추천을 쓰고 추천 순서·표지·도서 정보를 홈 모델로 연결한다")
    func coldStartPreservesRankingAndCovers() async throws {
        let first = Self.recommendation("1")
        let second = Self.recommendation("2")
        let books = try await withDependencies {
            $0.bookFavoritesClient.load = { [] }
            $0.searchHistoryClient.load = { [] }
            $0.coldStartRecommendationClient.fetch = { interests in
                #expect(interests == ColdStartRecommendation.placeholderInterests)
                return [first, second, first, Self.recommendation("3")]
            }
            $0.personalizedRecommendationClient.fetch = { _ in
                Issue.record("기록이 없으면 맞춤 추천을 호출하면 안 된다")
                return []
            }
            $0.bookClient.search = { query in
                #expect(query == "1 OR 2")
                return [Self.book("2"), Self.book("9"), Self.book("1")]
            }
        } operation: {
            try await BookRecommendationClient.liveValue.fetch(2)
        }
        #expect(books.map(\.id) == ["primo:alma1", "primo:alma2"])
        #expect(books.map(\.imageURL) == [first.coverImageURL, second.coverImageURL])
        #expect(books[0].title == Self.book("1").title)
        #expect(books[0].author == Self.book("1").author)
        #expect(books[0].recordKey == Self.book("1").recordKey)
    }

    @Test("찜·검색 기록을 맞춤 추천에 전달하고 첫 추천은 호출하지 않는다")
    func personalizedReceivesUserHistory() async throws {
        let recommendation = Self.recommendation("1")
        let books = try await withDependencies {
            $0.bookFavoritesClient.load = { [["control", "primo:alma9"]] }
            $0.searchHistoryClient.load = { ["반도체"] }
            $0.personalizedRecommendationClient.fetch = { input in
                #expect(input.favoriteKeys == [["control", "primo:alma9"]])
                #expect(input.recentQueries == ["반도체"])
                #expect(input.interests == ColdStartRecommendation.placeholderInterests)
                return [recommendation]
            }
            $0.coldStartRecommendationClient.fetch = { _ in
                Issue.record("맞춤 추천 성공 후 첫 추천을 호출하면 안 된다")
                return []
            }
            $0.bookClient.search = { _ in [Self.book("1")] }
        } operation: {
            try await BookRecommendationClient.liveValue.fetch(6)
        }
        #expect(books.map(\.id) == ["primo:alma1"])
        #expect(books.first?.imageURL == recommendation.coverImageURL)
    }

    @Test("맞춤 추천 오류·빈 결과는 첫 추천으로 대체한다", arguments: [false, true])
    func fallsBackToColdStart(throwsError: Bool) async throws {
        let recommendation = Self.recommendation("9")
        let books = try await withDependencies {
            $0.searchHistoryClient.load = { ["스위프트"] }
            $0.personalizedRecommendationClient.fetch = { _ in
                if throwsError { throw PersonalizedRecommendationError.noKeywords }
                return []
            }
            $0.coldStartRecommendationClient.fetch = { _ in [recommendation] }
            $0.bookClient.search = { query in
                #expect(query == "9")
                return [Self.book("9")]
            }
        } operation: {
            try await BookRecommendationClient.liveValue.fetch(6)
        }
        #expect(books.map(\.id) == ["primo:alma9"])
    }

    @Test("취소된 맞춤 추천은 첫 추천이나 메타데이터 요청을 새로 시작하지 않는다")
    func cancellationDoesNotFallBack() async {
        do {
            _ = try await withDependencies {
                $0.searchHistoryClient.load = { ["스위프트"] }
                $0.personalizedRecommendationClient.fetch = { _ in throw CancellationError() }
                $0.coldStartRecommendationClient.fetch = { _ in
                    Issue.record("취소 후 첫 추천을 호출하면 안 된다")
                    return []
                }
                $0.bookClient.search = { _ in
                    Issue.record("취소 후 메타데이터를 요청하면 안 된다")
                    return []
                }
            } operation: {
                try await BookRecommendationClient.liveValue.fetch(6)
            }
            Issue.record("취소 오류가 전달되어야 한다")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test("메타데이터 응답에 없는 책은 다른 책으로 대체하지 않는다")
    func excludesUnresolvedRecords() async throws {
        let books = try await withDependencies {
            $0.coldStartRecommendationClient.fetch = { _ in [Self.recommendation("1")] }
            $0.bookClient.search = { _ in [Self.book("9")] }
        } operation: {
            try await BookRecommendationClient.liveValue.fetch(6)
        }
        #expect(books.isEmpty)
    }

    private nonisolated static func recommendation(_ id: String) -> RecommendedBook {
        RecommendedBook(recordID: "alma\(id)", coverImageURL: URL(string: "https://covers.example.com/\(id).png")!)
    }

    private nonisolated static func book(_ id: String) -> Book {
        Book(
            id: "primo:alma\(id)", isbn: nil, controlNumber: "primo:alma\(id)",
            title: "제목 \(id)", author: "저자 \(id)", publisher: "출판사", publicationYear: "2026",
            description: nil, imageURL: URL(string: "https://unverified.example.com/\(id).png")
        )
    }
}
