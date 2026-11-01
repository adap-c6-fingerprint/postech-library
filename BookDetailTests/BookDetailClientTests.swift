import Foundation
import Testing
@testable import fingerprint_library

struct BookDetailClientTests {
    private let isbn = "9788966260959"

    private func service(_ body: String, status: Int = 200) -> Yes24BookDetailService {
        Yes24BookDetailService(relay: .test { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                            httpVersion: nil, headerFields: nil)!)
        })
    }

    @Test("ISBN13과 인증 헤더를 보내고 일치하는 책의 소개와 원문 링크만 반환한다")
    func requestAndMatchingBook() async throws {
        let body = #"{"success":true,"data":{"items":[{"isbn13":"9780131103627","link":"https://www.yes24.com/product/goods/2","contentDetail":{"bookIntroduction":"다른 책"}},{"isbn13":"9788966260959","link":"https://www.yes24.com/product/goods/1","contentDetail":{"bookIntroduction":"<p>선택한 책<br>소개 &amp; 설명</p>"}}]}}"#
        let client = Yes24BookDetailService(relay: .test { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.scheme == "https")
            #expect(components.host == "pobook-api-dev.fpmaps.com")
            #expect(components.path == "/yes24/v1/goods/itemDetail")
            #expect(components.queryItems == [URLQueryItem(name: "searchType", value: "ISBN13"),
                                             URLQueryItem(name: "query", value: "9788966260959")])
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-relay-token-not-a-provider-key")
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200,
                                                   httpVersion: nil, headerFields: nil)!)
        })
        let result = try await client.fetchDescription(isbn13: isbn)
        #expect(result?.text == "선택한 책\n소개 & 설명")
        #expect(result?.sourceURL == URL(string: "https://www.yes24.com/product/goods/1"))
    }

    @Test("다른 ISBN, 비어 있는 소개, 누락된 소개를 빈 결과로 처리한다", arguments: [
        #"{"success":true,"data":{"items":[]}}"#,
        #"{"success":true,"data":{"items":[{"isbn13":"9780131103627","contentDetail":{"bookIntroduction":"다른 책"}}]}}"#,
        #"{"success":true,"data":{"items":[{"isbn13":"9788966260959","contentDetail":null}]}}"#,
        #"{"success":true,"data":{"items":[{"isbn13":"9788966260959","contentDetail":{"bookIntroduction":"<p>&nbsp;</p>"}}]}}"#
    ])
    func missingIntroduction(body: String) async throws {
        #expect(try await service(body).fetchDescription(isbn13: isbn) == nil)
    }

    @Test("상품이 없다는 404만 빈 결과로 처리한다", arguments: ["GOODS_001", "GOODS_002"])
    func missingProduct(code: String) async throws {
        let body = "{\"success\":false,\"errorCode\":\"\(code)\"}"
        #expect(try await service(body, status: 404).fetchDescription(isbn13: isbn) == nil)
    }

    @Test("서버 검색 오류, 인증 오류, 잘못된 JSON, 실패 응답은 오류로 처리한다", arguments: [
        (404, #"{"success":false,"errorCode":"SEARCH_002"}"#),
        (401, #"{"success":false,"errorCode":"AUTH_001"}"#),
        (200, "invalid json"),
        (200, #"{"success":false,"errorCode":"COMMON_001"}"#),
        (200, #"{"success":true,"data":null}"#)
    ])
    func serviceFailure(sample: (Int, String)) async {
        await #expect(throws: (any Error).self) {
            try await service(sample.1, status: sample.0).fetchDescription(isbn13: isbn)
        }
    }

    @Test("소개에 연결할 Yes24 상품 링크가 없거나 다른 사이트이면 오류로 처리한다", arguments: [
        "https://yes24.com.example.org/product/1", "http://www.yes24.com/product/1", ""
    ])
    func invalidSourceLink(link: String) async {
        let body = "{\"success\":true,\"data\":{\"items\":[{\"isbn13\":\"\(isbn)\",\"link\":\"\(link)\",\"contentDetail\":{\"bookIntroduction\":\"소개\"}}]}}"
        await #expect(throws: (any Error).self) {
            try await service(body).fetchDescription(isbn13: isbn)
        }
    }
}
