import Foundation
import Testing
@testable import fingerprint_library

nonisolated struct RecommendationBoundaryTests {
    @Test("추천용 Primo 조회는 성공 본문을 반환하고 HTTP 오류는 거절한다", arguments: [200, 503])
    func validatesPrimoSearchData(status: Int) async throws {
        let api = PrimoAPIClient(relay: .test { request in
            (Data("response".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        if status == 200 {
            #expect(try await api.searchData(query: "any,contains,과학") == Data("response".utf8))
        } else {
            await #expect(throws: PrimoAPIError.self) {
                try await api.searchData(query: "any,contains,과학")
            }
        }
    }

    @Test("같은 후보도 첫 추천은 표지 출처를, 맞춤 추천은 후보 순위를 우선한다")
    func keepsSelectionPoliciesDistinct() async {
        let candidates = [
            ColdStartCandidate(recordID: "primo", primoCoverURL: URL(string: "https://covers.example.com/first"), isbn13: nil),
            ColdStartCandidate(recordID: "data4", primoCoverURL: nil, isbn13: "isbn-second")
        ].map(RecommendationCoverSelector.Candidate.init)
        let resolver = RecommendationCoverResolver(
            data4LibraryLookup: { URL(string: "https://d4l.example.com/\($0).jpg") },
            isRealImage: { _ in true }
        )
        let first = await RecommendationCoverSelector.select(
            candidates, policy: .preferData4Library, limit: 2, batchSize: 10, resolver: resolver
        )
        let ranked = await RecommendationCoverSelector.select(
            candidates, policy: .preserveRanking, limit: 2, batchSize: 10, resolver: resolver
        )
        #expect(first.map(\.recordID) == ["data4", "primo"])
        #expect(ranked.map(\.recordID) == ["primo", "data4"])
    }

    @Test("첫 추천은 total을 요구하고 display 없는 후보도 허용한다")
    func keepsColdStartResponseContract() throws {
        let doc = #"{"pnx":{"control":{"recordid":["a"]},"addata":{"isbn":["9788966260959"]}},"delivery":{"holding":[{"callNumber":"Q1"}]}}"#
        let valid = Data("{\"info\":{\"total\":1},\"docs\":[\(doc)]}".utf8)
        #expect(try PrimoRecommendationMapper.coldStartPage(from: valid, codes: ["Q"]).candidates.count == 1)
        let missingTotal = Data("{\"docs\":[\(doc)]}".utf8)
        #expect(throws: (any Error).self) {
            try PrimoRecommendationMapper.coldStartPage(from: missingTotal, codes: ["Q"])
        }
    }

    @Test("맞춤 추천은 total 없이 조회할 수 있고 display 누락은 오류로 처리한다")
    func keepsPersonalizedResponseContract() throws {
        let missingDisplay = Data(#"{"docs":[{"pnx":{"control":{"recordid":["a"]}},"delivery":{"holding":[{"callNumber":"Q1"}]}}]}"#.utf8)
        #expect(throws: (any Error).self) {
            try PrimoRecommendationMapper.personalizedCandidates(from: missingDisplay)
        }
        #expect(try PrimoRecommendationMapper.titles(from: Data(#"{"docs":[{"pnx":{"control":{"recordid":["a"]},"display":{"title":["<b>책</b>"]}}}]}"#.utf8)) == ["책"])
    }

    @Test("정보나루 표지 응답 변환은 API 계층에서 수행하고 http 주소를 보정한다")
    func decodesData4LibraryCover() async throws {
        let api = Data4LibraryAPIClient(relay: .test { request in
            #expect(request.url?.path == "/data4library/api/srchDtlList")
            let body = #"{"response":{"detail":[{"book":{"bookImageURL":"http://covers.example.com/book.jpg"}}]}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await api.coverURL(isbn13: "9788966260959")
                == URL(string: "https://covers.example.com/book.jpg"))
    }

    @Test("표지 미제공은 nil이고 HTTP 장애와 잘못된 JSON은 오류다", arguments: [200, 503])
    func distinguishesMissingCoverFromFailure(status: Int) async throws {
        let api = Data4LibraryAPIClient(relay: .test { request in
            (Data(#"{"response":{"detail":[]}}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        if status == 200 {
            #expect(try await api.coverURL(isbn13: "9788966260959") == nil)
        } else {
            await #expect(throws: Data4LibraryAPIError.self) {
                try await api.coverURL(isbn13: "9788966260959")
            }
        }
        let malformed = Data4LibraryAPIClient(relay: .test { request in
            (Data("invalid JSON".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: (any Error).self) {
            try await malformed.coverURL(isbn13: "9788966260959")
        }
    }

    @Test("공통 표지 조회는 공급처 오류를 fallback 가능한 nil로 바꾼다")
    func resolverAllowsFallbackAfterLookupFailure() async {
        let resolver = RecommendationCoverResolver.live(
            httpClient: HTTPClient(load: { _ in throw URLError(.timedOut) }),
            minimumImageBytes: 1_000
        )
        #expect(await resolver.data4LibraryLookup("9788966260959") == nil)
    }

    @Test("이미지 응답은 HTTP 상태·MIME·최소 크기를 함께 검사한다",
          arguments: [(200, "image/png", 1_000, true), (200, "image/png", 999, false),
                      (200, "text/html", 1_000, false), (403, "image/png", 1_000, false)])
    func validatesImageResponse(sample: (Int, String, Int, Bool)) async {
        let resolver = RecommendationCoverResolver.live(
            httpClient: HTTPClient(load: { request in
                (Data(repeating: 1, count: sample.2), HTTPURLResponse(
                    url: request.url!, statusCode: sample.0, httpVersion: nil,
                    headerFields: ["Content-Type": sample.1]
                )!)
            }),
            minimumImageBytes: 1_000
        )
        #expect(await resolver.isRealImage(URL(string: "https://covers.example.com/book")!) == sample.3)
    }
}
