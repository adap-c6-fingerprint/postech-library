import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

nonisolated struct BookAPITransportTests {
    @Test("도서관·Yes24·정보나루가 주입한 동일 HTTP 전송기를 사용한다")
    func sharesTransportAcrossProviders() async throws {
        let hosts = Mutex<[String]>([])
        let client = HTTPClient(load: { request in
            let url = try #require(request.url)
            hosts.withLock { $0.append(url.host!) }
            let body = url.host == "apis.yes24.com"
                ? #"{"success":true,"data":{"items":[{"isbn13":"9788937460777","cover":"https://image.yes24.com/goods/372300/L"}]}}"#
                : #"{"docs":[]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await PrimoAPIClient(httpClient: client, apiKey: "primo-key").search(query: "any,contains,과학")
        let cover = try await Yes24BookDetailService(httpClient: client)
            .fetchCoverURL(isbn13: "9788937460777", apiKey: "yes24-key")
        _ = try await Data4LibraryAPIClient(httpClient: client)
            .fetch(.relatedBooks, isbn13: "9788937460777", apiKey: "data4-key")
        #expect(cover?.host == "image.yes24.com")
        #expect(hosts.withLock { $0 } == ["api-ap.hosted.exlibrisgroup.com", "apis.yes24.com", "data4library.kr"])
    }

    @Test("추천용 분류·페이지·개수를 보존하며 프록시 하위 경로에도 요청한다")
    func preservesPrimoRequestConfiguration() async throws {
        let client = HTTPClient(load: { request in
            let url = try #require(request.url)
            #expect(url.absoluteString.hasPrefix("https://proxy.test/library/primo/v1/search?"))
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            #expect(value("q") == "any,contains,과학 & 역사 OR QA1*")
            #expect(value("multiFacets") == "facet_rtype,include,printed_book")
            #expect(value("offset") == "50")
            #expect(value("limit") == "50")
            #expect(value("skipDelivery") == "false")
            #expect(value("scope") == "MyInstitution")
            #expect(value("apikey") == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "apikey primo-key")
            #expect(request.timeoutInterval == 15)
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await PrimoAPIClient(
            httpClient: client, baseURL: URL(string: "https://proxy.test/library")!, apiKey: "primo-key"
        ).search(query: "any,contains,과학 & 역사 OR QA1*", resourceTypes: ["printed_book"], offset: 50, limit: 50, timeout: 15)
    }

    @Test("정보나루 인증과 연관 도서 유형을 올바른 엔드포인트에만 전달한다",
          arguments: [Data4LibraryAPIClient.Endpoint.relatedBooks, .bookDetail])
    func preservesData4LibraryRequest(endpoint: Data4LibraryAPIClient.Endpoint) async throws {
        let client = HTTPClient(load: { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first { $0.name == "authKey" }?.value == "key&with+symbols")
            #expect(query.first { $0.name == "isbn13" }?.value == "9788937460777")
            #expect(query.first { $0.name == "format" }?.value == "json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            if case .relatedBooks = endpoint {
                #expect(url.path == "/api/recommandList")
                #expect(query.first { $0.name == "type" }?.value == "mania")
            } else {
                #expect(url.path == "/api/srchDtlList")
                #expect(query.first { $0.name == "type" } == nil)
            }
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await Data4LibraryAPIClient(httpClient: client)
            .fetch(endpoint, isbn13: "9788937460777", apiKey: "key&with+symbols")
    }
}
