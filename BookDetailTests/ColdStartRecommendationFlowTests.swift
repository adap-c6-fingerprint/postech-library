import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

@MainActor
struct ColdStartRecommendationFlowTests {
    @Test("첫 추천 전체 흐름은 0번 페이지를 재사용하고 정보나루 표지를 먼저 선택한다")
    func reusesFirstPageAndPrefersData4Library() async throws {
        let offsets = Mutex<[Int]>([])
        let response = Data(#"{"info":{"total":2},"docs":[{"pnx":{"control":{"recordid":["primo"]}},"delivery":{"holding":[{"callNumber":"Q1"}],"link":[{"linkType":"thumbnail","linkURL":"https://covers.example.com/primo"}]}},{"pnx":{"control":{"recordid":["data4"]},"addata":{"isbn":["9788966260959"]}},"delivery":{"holding":[{"callNumber":"Q1"}]}}]}"#.utf8)
        let books = try await ColdStartRecommendationService.recommend(
            interests: [" q "],
            dependencies: .init(
                searchPrimo: { query, offset in
                    #expect(query.hasPrefix("any,contains,Q1* OR "))
                    offsets.withLock { $0.append(offset) }
                    return response
                },
                covers: .init(
                    data4LibraryLookup: { URL(string: "https://d4l.example.com/\($0).jpg") },
                    isRealImage: { _ in true }
                ),
                chooseOffset: { _ in 0 }
            )
        )
        #expect(offsets.withLock { $0 } == [0])
        #expect(books.map(\.recordID) == ["data4", "primo"])
    }

    @Test("추가 페이지 상한을 지키고 이전 페이지의 후보를 다시 표지 조회하지 않는다")
    func boundsPagesAndDeduplicatesCandidates() async throws {
        let offsets = Mutex<[Int]>([])
        let choices = Mutex([20, 40])
        let covers = Mutex(0)
        let books = try await ColdStartRecommendationService.recommend(
            interests: ["Q"],
            dependencies: .init(
                searchPrimo: { _, offset in
                    offsets.withLock { $0.append(offset) }
                    switch offset {
                    case 0: return Self.page(ids: [])
                    case 20: return Self.page(ids: ["a"])
                    default: return Self.page(ids: ["a", "b"])
                    }
                },
                covers: .init(
                    data4LibraryLookup: { _ in
                        covers.withLock { $0 += 1 }
                        return URL(string: "https://d4l.example.com/cover.jpg")
                    },
                    isRealImage: { _ in false }
                ),
                chooseOffset: { _ in choices.withLock { $0.removeFirst() } }
            )
        )
        #expect(offsets.withLock { $0 } == [0, 20, 40])
        #expect(books.map(\.recordID) == ["a", "b"])
        #expect(covers.withLock { $0 } == 2)
    }

    @Test("유효한 관심사가 없으면 조회를 시작하지 않는다")
    func rejectsEmptyInterestsBeforeLoading() async {
        let dependencies = ColdStartRecommendationService.Dependencies(
            searchPrimo: { _, _ in
                Issue.record("관심사가 없으면 검색하면 안 된다")
                return Data()
            },
            covers: .init(data4LibraryLookup: { _ in nil }, isRealImage: { _ in false })
        )
        await #expect(throws: RecommendationClientError.noInterests) {
            try await ColdStartRecommendationService.recommend(interests: [" ", "가"], dependencies: dependencies)
        }
    }

    private nonisolated static func page(ids: [String]) -> Data {
        let docs = ids.map { id in
            #"{"pnx":{"control":{"recordid":["\#(id)"]},"addata":{"isbn":["9788966260959"]}},"delivery":{"holding":[{"callNumber":"Q1"}]}}"#
        }.joined(separator: ",")
        return Data("{\"info\":{\"total\":150},\"docs\":[\(docs)]}".utf8)
    }
}
