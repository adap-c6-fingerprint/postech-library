import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

nonisolated struct BookAPITransportTests {
    @Test("세 공급자의 모든 요청은 같은 중계 호스트와 Bearer 인증을 사용한다")
    func sharesTransportAcrossProviders() async throws {
        let paths = Mutex<[String]>([])
        let relay = BookAPIClient.test { request in
            let url = try #require(request.url)
            #expect(url.host == "pobook-api-dev.fpmaps.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-relay-token-not-a-provider-key")
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { ["apikey", "authKey"].contains($0.name) }) == false)
            paths.withLock { $0.append(url.path) }
            let body = url.path.contains("yes24")
                ? #"{"success":true,"data":{"items":[{"isbn13":"9788937460777","cover":"https://image.yes24.com/goods/372300/L"}]}}"#
                : #"{"docs":[]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await PrimoAPIClient(relay: relay).search(query: "any,contains,과학")
        let cover = try await Yes24BookDetailService(relay: relay).fetchCoverURL(isbn13: "9788937460777")
        _ = try await Data4LibraryAPIClient(relay: relay).fetch(.relatedBooks, isbn13: "9788937460777")
        #expect(cover?.host == "image.yes24.com")
        #expect(paths.withLock { $0 } == ["/primo/v1/search", "/yes24/v1/goods/itemDetail", "/data4library/api/recommandList"])
    }

    @Test("추천용 검색어·분류·페이지·개수와 타임아웃을 보존한다")
    func preservesPrimoRequestConfiguration() async throws {
        let relay = BookAPIClient.test { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            #expect(value("q") == "any,contains,과학 & 역사 OR QA1*")
            #expect(value("multiFacets") == "facet_rtype,include,printed_book")
            #expect(value("offset") == "50")
            #expect(value("limit") == "50")
            #expect(value("skipDelivery") == "false")
            #expect(value("scope") == "MyInstitution")
            #expect(value("apikey") == nil)
            #expect(request.timeoutInterval == 15)
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await PrimoAPIClient(relay: relay).search(query: "any,contains,과학 & 역사 OR QA1*", resourceTypes: ["printed_book"], offset: 50, limit: 50, timeout: 15)
    }

    @Test("정보나루 요청은 인증키 없이 기존 ISBN·유형·출력 형식을 전달한다",
          arguments: [Data4LibraryAPIClient.Endpoint.relatedBooks, .bookDetail])
    func preservesData4LibraryRequest(endpoint: Data4LibraryAPIClient.Endpoint) async throws {
        let relay = BookAPIClient.test { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first { $0.name == "authKey" } == nil)
            #expect(query.first { $0.name == "isbn13" }?.value == "9788937460777")
            #expect(query.first { $0.name == "format" }?.value == "json")
            if case .relatedBooks = endpoint {
                #expect(url.path == "/data4library/api/recommandList")
                #expect(query.first { $0.name == "type" }?.value == "mania")
            } else {
                #expect(url.path == "/data4library/api/srchDtlList")
                #expect(query.first { $0.name == "type" } == nil)
            }
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await Data4LibraryAPIClient(relay: relay).fetch(endpoint, isbn13: "9788937460777")
    }

    @Test("내부·TestFlight·App Store는 서로 다른 호스트와 해당 토큰만 사용한다",
          arguments: [APIRelayEnvironment.development, .testFlight, .production])
    func isolatesEnvironment(environment: APIRelayEnvironment) async throws {
        let relay = BookAPIClient(httpClient: HTTPClient(load: { request in
            #expect(request.url?.host == environment.baseURL.host)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(environment.rawValue)-token-with-at-least-32-characters")
            return (Data("upstream".utf8), HTTPURLResponse(url: request.url!, statusCode: 429,
                httpVersion: nil, headerFields: ["Retry-After": "120"])!)
        }), configuration: { .init(environment: environment, token: "\(environment.rawValue)-token-with-at-least-32-characters") })
        let response = try await relay.send(.primoSearch, queryItems: [URLQueryItem(name: "q", value: "과학 & 역사")])
        #expect(response.response.statusCode == 429)
        #expect(response.response.value(forHTTPHeaderField: "Retry-After") == "120")
        #expect(response.data == Data("upstream".utf8))
    }

    @Test("배포 환경은 Debug/내부 우선, TestFlight sandbox, App Store production으로 선택한다")
    func selectsDistribution() throws {
        #expect(try APIRelayEnvironment.select(internalBuild: true, distribution: nil) == .development)
        #expect(try APIRelayEnvironment.select(internalBuild: true, distribution: .production) == .development)
        #expect(try APIRelayEnvironment.select(internalBuild: false, distribution: .xcode) == .development)
        #expect(try APIRelayEnvironment.select(internalBuild: false, distribution: .sandbox) == .testFlight)
        #expect(try APIRelayEnvironment.select(internalBuild: false, distribution: .production) == .production)
        #expect(throws: APIRelayError.self) { try APIRelayEnvironment.select(internalBuild: false, distribution: nil) }
        #expect(APIRelayEnvironment.testFlight.baseURL.host == "pobook-api-testfligh.fpmaps.com")
    }

    @Test("접근 토큰 누락·헤더 주입·제공사 인증키는 네트워크 전에 차단한다")
    func rejectsUnsafeCredentials() async {
        let network = HTTPClient(load: { _ in Issue.record("네트워크를 호출하면 안 됨"); throw URLError(.badURL) })
        for token in ["", "short", "token-with-at-least-32-characters\r\nInjected: 1"] {
            let relay = BookAPIClient(httpClient: network, configuration: { .init(environment: .development, token: token) })
            await #expect(throws: APIRelayError.self) { try await relay.send(.primoSearch, queryItems: []) }
        }
        let relay = BookAPIClient(httpClient: network, configuration: {
            .init(environment: .development, token: "valid-token-with-at-least-32-characters")
        })
        for key in ["apikey", "authKey", "APIKEY"] {
            await #expect(throws: APIRelayError.self) {
                try await relay.send(.primoSearch, queryItems: [URLQueryItem(name: key, value: "provider-secret")])
            }
        }
    }

    @Test("환경 확인 실패는 다른 서버로 우회하지 않는다")
    func doesNotFallbackAcrossEnvironments() async {
        let relay = BookAPIClient(httpClient: HTTPClient(load: { _ in Issue.record("우회 요청 금지"); throw URLError(.badURL) }), configuration: {
            throw APIRelayError.unknownDistribution
        })
        await #expect(throws: APIRelayError.self) { try await relay.send(.primoSearch, queryItems: []) }
    }
}
