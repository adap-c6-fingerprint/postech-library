import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct PersonalizedRecommendationTests {
    @Test("찜이나 최근 검색 중 하나라도 있으면 맞춤 추천을 쓴다")
    func shouldApply() {
        #expect(!PersonalizedRecommendation.shouldApply(favoriteKeys: [], recentQueries: []))
        #expect(PersonalizedRecommendation.shouldApply(favoriteKeys: [["control", "primo:alma1"]], recentQueries: []))
        #expect(PersonalizedRecommendation.shouldApply(favoriteKeys: [], recentQueries: ["반도체"]))
    }

    @Test("찜 키에서 Primo 검색용 레코드 번호와 제목을 꺼낸다")
    func favoriteKeys() {
        let keys: Set<[String?]> = [
            ["control", "primo:alma991003618878303286"],
            ["control", "primo:alma991000849479703286"],
            ["control", "local:abc"],
            ["metadata", "9788966260959", "스위프트 입문", "저자", nil, "2020"],
            ["metadata", nil, nil, "저자", nil, nil],
        ]
        #expect(PersonalizedRecommendation.favoriteMMSIDs(keys) == ["991000849479703286", "991003618878303286"])
        #expect(PersonalizedRecommendation.favoriteMetadataTitles(keys) == ["스위프트 입문"])
        #expect(PersonalizedRecommendation.primoRecordQuery(["1", "2"]) == "any,contains,1 OR 2")
    }

    @Test("키워드는 검색 특수문자를 지우고 중복 없이 5개까지만 쓴다")
    func normalizedKeywords() {
        let keywords = PersonalizedRecommendation.normalizedKeywords([
            " 양자  역학 ", "반도체,소자", "머신러닝", "머신러닝", "AI OR 철학", "", "(소설)", "통계", "여분"
        ])
        #expect(keywords == ["양자 역학", "반도체 소자", "머신러닝", "AI 철학", "소설"])
        #expect(PersonalizedRecommendation.primoKeywordQuery(["반도체", "양자 역학"]) == "any,contains,반도체 OR 양자 역학")
    }

    @Test("모델 순서의 잘못된 번호는 버리고 빠진 책은 원래 순서로 뒤에 붙인다")
    func mergedRanking() {
        #expect(PersonalizedRecommendation.mergedRanking(modelOrder: [3, 1, 3, 9, 0], count: 4) == [2, 0, 1, 3])
        #expect(PersonalizedRecommendation.mergedRanking(modelOrder: [], count: 3) == [0, 1, 2])
    }

    @Test("관심 분류에 속한 책을 모델 순서를 유지한 채 앞으로 모은다")
    func prioritized() {
        let candidates = [
            candidate("h1", callNumber: "HG1615 .L67"),
            candidate("q1", callNumber: "QC174.12 .박95"),
            candidate("t1", callNumber: "TK7871.85"),
            candidate("q2", callNumber: "Q325.5 .M87"),
        ]
        let result = PersonalizedRecommendation.prioritized(candidates, ranking: [2, 3, 0, 1], interestCodes: ["Q"])
        #expect(result.map(\.recordID) == ["q2", "q1", "t1", "h1"])
    }

    @Test("모델 입력에 번호·제목·관심분류 표시를 넣는다")
    func rankingPrompt() {
        let prompt = PersonalizedRecommendation.rankingPrompt(
            [candidate("q1", callNumber: "QC174", subject: "양자론"), candidate("h1", callNumber: "HG1")],
            keywords: ["양자역학", "금융"],
            interestCodes: ["Q"]
        )
        #expect(prompt.contains("관심 키워드: 양자역학, 금융"))
        #expect(prompt.contains("1. 책 q1 (양자론) [관심분류]"))
        #expect(prompt.contains("2. 책 h1\n") || prompt.hasSuffix("2. 책 h1"))
    }

    @Test("키워드 검색 응답에서 조건에 맞는 후보만 남긴다")
    func parseCandidates() throws {
        let json = """
        {"docs":[
          {"pnx":{"control":{"recordid":["alma1"]},"display":{"title":["<b>머신</b> 러닝 "],"subject":["기계학습"]},
                  "addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[{"callNumber":" Q325.5 .M87 "}]}},
          {"pnx":{"control":{"recordid":["alma2"]},"display":{"title":["청구기호 없음"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[]}},
          {"pnx":{"control":{"recordid":["alma3"]},"display":{"title":["표지 없음"]}},
           "delivery":{"holding":[{"callNumber":"QA76"}]}},
          {"pnx":{"control":{"recordid":["alma4"]},"display":{"title":["4libs만"]}},
           "delivery":{"holding":[{"callNumber":"HG1"}],
                       "link":[{"linkType":"thumbnail","linkURL":"https://covers.example.com/4.jpg"}]}},
          {"pnx":{"control":{"recordid":["alma1"]},"display":{"title":["중복"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[{"callNumber":"Q1"}]}}
        ]}
        """
        let candidates = try PersonalizedRecommendationService.parseCandidates(Data(json.utf8))
        #expect(candidates == [
            PersonalizedCandidate(recordID: "alma1", title: "머신 러닝", subject: "기계학습",
                                  callNumber: "Q325.5 .M87", primoCoverURL: nil, isbn13: "9788966260959"),
            PersonalizedCandidate(recordID: "alma4", title: "4libs만", subject: nil, callNumber: "HG1",
                                  primoCoverURL: URL(string: "https://covers.example.com/4.jpg"), isbn13: nil),
        ])
    }

    @Test("표지는 우선순위 순서로 책마다 정보나루 → 4libs 순서로 확인한다")
    func topBooksWithCovers() async {
        let ranked = [
            candidate("r1", isbn13: nil, primo: "https://4libs.example.com/r1"),
            candidate("r2", isbn13: "isbn-r2", primo: nil),
            candidate("r3", isbn13: "isbn-none", primo: "https://4libs.example.com/empty"),
            candidate("r4", isbn13: "isbn-none", primo: "https://4libs.example.com/r4"),
        ]
        let books = await PersonalizedRecommendationService.topBooksWithCovers(
            ranked,
            limit: 3,
            data4LibraryLookup: { $0 == "isbn-r2" ? URL(string: "https://d4l.example.com/r2.jpg") : nil },
            isRealImage: { $0.lastPathComponent != "empty" }
        )
        // 첫 추천처럼 정보나루 표지를 먼저 모으면 r2가 1위가 된다. 여기서는 순위가 높은 r1이 먼저다.
        #expect(books.map(\.recordID) == ["r1", "r2", "r4"])
        #expect(books[1].coverImageURL == URL(string: "https://d4l.example.com/r2.jpg"))
    }

    @Test("6권이 모이면 다음 묶음의 표지는 확인하지 않는다")
    func coverBatchesStop() async {
        let checked = LockIsolated(0)
        let ranked = (1...25).map { candidate("n\($0)", isbn13: "isbn-\($0)", primo: nil) }
        let books = await PersonalizedRecommendationService.topBooksWithCovers(
            ranked,
            data4LibraryLookup: { isbn in
                checked.withValue { $0 += 1 }
                return URL(string: "https://d4l.example.com/\(isbn).jpg")
            },
            isRealImage: { _ in true }
        )
        #expect(books.map(\.recordID) == ["n1", "n2", "n3", "n4", "n5", "n6"])
        #expect(checked.value == 10)
    }

    @Test("전체 흐름: 찜 제목 조회 → 모델 키워드 → 50권 검색 → 모델 정렬 → 관심 분류 우선 → 표지")
    func recommendFlow() async throws {
        let queries = LockIsolated<[(String, Int)]>([])
        let keywordPrompts = LockIsolated<[String]>([])
        let books = try await PersonalizedRecommendationService.recommend(
            PersonalizedRecommendationInput(
                favoriteKeys: [["control", "primo:alma991"]],
                recentQueries: ["반도체 공정"],
                interests: ["Q"]
            ),
            dependencies: .init(
                model: FoundationModelsClient(
                    isAvailable: { true },
                    extractKeywords: { prompt in
                        keywordPrompts.withValue { $0.append(prompt) }
                        return ["반도체", "양자역학"]
                    },
                    rankBooks: { _ in [3, 1, 2] }
                ),
                searchPrimo: { query, limit in
                    queries.withValue { $0.append((query, limit)) }
                    return query.contains("991") ? Self.titleResponse : Self.searchResponse
                },
                data4LibraryLookup: { URL(string: "https://d4l.example.com/\($0).jpg") },
                isRealImage: { _ in true }
            )
        )
        #expect(queries.value.map(\.0) == ["any,contains,991", "any,contains,반도체 OR 양자역학"])
        #expect(queries.value.map(\.1) == [1, 50])
        #expect(keywordPrompts.value.first?.contains("- 반도체 소자 공학") == true)
        #expect(keywordPrompts.value.first?.contains("- 반도체 공정") == true)
        // 모델 순서는 c, a, b. 그중 관심 분류(Q)인 b를 맨 앞으로 모은다.
        #expect(books.map(\.recordID) == ["b", "c", "a"])
    }

    @Test("모델을 쓸 수 없으면 최근 검색어·찜 제목을 키워드로 쓰고 포스텍 순서를 유지한다")
    func recommendWithoutModel() async throws {
        let queries = LockIsolated<[String]>([])
        let books = try await PersonalizedRecommendationService.recommend(
            PersonalizedRecommendationInput(favoriteKeys: [], recentQueries: ["반도체", "양자역학"], interests: []),
            dependencies: .init(
                model: FoundationModelsClient(
                    isAvailable: { false },
                    extractKeywords: { _ in
                        Issue.record("모델을 부르면 안 된다")
                        return []
                    },
                    rankBooks: { _ in
                        Issue.record("모델을 부르면 안 된다")
                        return []
                    }
                ),
                searchPrimo: { query, _ in
                    queries.withValue { $0.append(query) }
                    return Self.searchResponse
                },
                data4LibraryLookup: { URL(string: "https://d4l.example.com/\($0).jpg") },
                isRealImage: { _ in true }
            )
        )
        #expect(queries.value == ["any,contains,반도체 OR 양자역학"])
        #expect(books.map(\.recordID) == ["a", "b", "c"])
    }

    @Test("기록이 있으면 홈 화면이 맞춤 추천을 불러온다")
    func homeLoadsPersonalized() async {
        let book = RecommendedBook(recordID: "alma1", coverImageURL: URL(string: "https://c.example.com/1.jpg")!)
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.bookFavoritesClient.load = { [] }
            $0.searchHistoryClient.load = { ["반도체"] }
            $0.personalizedRecommendationClient.fetch = { input in
                #expect(input.recentQueries == ["반도체"])
                #expect(input.interests == ColdStartRecommendation.placeholderInterests)
                return [book]
            }
            $0.coldStartRecommendationClient.fetch = { _ in
                Issue.record("호출되면 안 된다")
                return []
            }
        }
        await store.send(.task)
        await store.receive(\.personalizedLoaded) { $0.personalizedBooks = [book] }
    }

    @Test("맞춤 추천이 실패하면 첫 추천으로 대신한다")
    func homeFallsBackToColdStart() async {
        let book = RecommendedBook(recordID: "alma9", coverImageURL: URL(string: "https://c.example.com/9.jpg")!)
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.bookFavoritesClient.load = { [["control", "primo:alma1"]] }
            $0.searchHistoryClient.load = { [] }
            $0.personalizedRecommendationClient.fetch = { _ in
                throw PersonalizedRecommendationError.noKeywords
            }
            $0.coldStartRecommendationClient.fetch = { _ in [book] }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        // 실패 메시지 문자열은 확인하지 않는다.
        await store.send(.task)
        await store.receive(\.personalizedFailed)
        await store.receive(\.coldStartLoaded) { $0.coldStartBooks = [book] }
    }

    // MARK: - 테스트 데이터

    private func candidate(
        _ id: String,
        callNumber: String = "Q1",
        subject: String? = nil,
        isbn13: String? = "isbn",
        primo: String? = nil
    ) -> PersonalizedCandidate {
        PersonalizedCandidate(
            recordID: id, title: "책 \(id)", subject: subject, callNumber: callNumber,
            primoCoverURL: primo.flatMap(URL.init(string:)), isbn13: isbn13
        )
    }

    private nonisolated static let titleResponse = Data("""
    {"docs":[{"pnx":{"control":{"recordid":["alma991"]},"display":{"title":["반도체 소자 공학 "]}}}]}
    """.utf8)

    private nonisolated static let searchResponse = Data("""
    {"docs":[
      {"pnx":{"control":{"recordid":["a"]},"display":{"title":["가"]},"addata":{"isbn":["9788966260959"]}},
       "delivery":{"holding":[{"callNumber":"TK7871"}]}},
      {"pnx":{"control":{"recordid":["b"]},"display":{"title":["나"]},"addata":{"isbn":["9788966260959"]}},
       "delivery":{"holding":[{"callNumber":"QC174"}]}},
      {"pnx":{"control":{"recordid":["c"]},"display":{"title":["다"]},"addata":{"isbn":["9788966260959"]}},
       "delivery":{"holding":[{"callNumber":"HG1"}]}}
    ]}
    """.utf8)
}
