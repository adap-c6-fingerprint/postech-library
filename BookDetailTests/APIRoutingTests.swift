import Foundation
import Testing
@testable import fingerprint_library

nonisolated struct APIRoutingTests {
    @Test("초기값은 서버 경유이고 제공사별 선택은 새 인스턴스에도 보존된다")
    func persistsIndependentSettings() throws {
        let suite = "APIRoutingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(APIRoutingSettings.load(from: defaults) == APIRoutingSettings())
        var settings = APIRoutingSettings()
        settings.primo = false
        settings.data4Library = false
        settings.save(to: defaults)
        let reloaded = APIRoutingSettings.load(from: try #require(UserDefaults(suiteName: suite)))
        #expect(reloaded == settings)
        #expect(reloaded.yes24)
    }

    @Test("직접 호출은 중계 설정 없이 제공사별 인증과 원래 쿼리를 사용한다",
          arguments: [BookAPIClient.Endpoint.primoSearch, .yes24Detail, .data4LibraryDetail, .data4LibraryRelated])
    func directRequests(endpoint: BookAPIClient.Endpoint) async throws {
        let client = BookAPIClient(httpClient: HTTPClient(load: { request in
            let url = try #require(request.url)
            #expect(url.host == endpoint.directURL.host)
            #expect(url.path == endpoint.directURL.path)
            #expect(request.timeoutInterval == 15)
            #expect(request.value(forHTTPHeaderField: "Accept") ==
                (endpoint.provider == .data4Library ? "*/*" : "application/json"))
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(items.first { $0.name == "q" }?.value == "과학 & 역사")
            switch endpoint.provider {
            case .primo:
                #expect(request.value(forHTTPHeaderField: "Authorization") == "apikey fake-provider-key")
                #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
            case .yes24:
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "fake-provider-key")
            case .data4Library:
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(items.first { $0.name == "authKey" }?.value == "fake-provider-key")
                #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
            }
            return (Data("unchanged".utf8), HTTPURLResponse(url: url, statusCode: 429,
                httpVersion: nil, headerFields: ["Retry-After": "60"])!)
        }), configuration: {
            Issue.record("직접 호출에는 중계 설정이 필요하지 않음")
            throw APIRelayError.missingAccessToken
        }, usesRelay: { _ in false }, providerKey: { _ in "fake-provider-key" })
        let result = try await client.send(endpoint, queryItems: [.init(name: "q", value: "과학 & 역사")], timeout: 15)
        #expect(result.data == Data("unchanged".utf8))
        #expect(result.response.statusCode == 429)
        #expect(result.response.value(forHTTPHeaderField: "Retry-After") == "60")
    }

    @Test("서버 경유에는 제공사 키가 필요 없고 토글은 각 제공사만 바꾼다")
    func mixedRouting() async throws {
        let client = BookAPIClient(httpClient: HTTPClient(load: { request in
            let url = try #require(request.url)
            let direct = url.host == "api-ap.hosted.exlibrisgroup.com"
            #expect(direct || url.host == "pobook-api-dev.fpmaps.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") ==
                (direct ? "apikey fake-primo-key" : "Bearer unit-test-relay-token-not-a-provider-key"))
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }), configuration: {
            .init(environment: .development, token: "unit-test-relay-token-not-a-provider-key")
        }, usesRelay: { $0.provider != .primo }, providerKey: { provider in
            #expect(provider == .primo)
            return "fake-primo-key"
        })
        for endpoint in [BookAPIClient.Endpoint.primoSearch, .yes24Detail, .data4LibraryDetail, .data4LibraryRelated] {
            _ = try await client.send(endpoint, queryItems: [])
        }
    }

    @Test("직접 호출 키 누락·헤더 주입은 통신 전에 실패하고 서버로 자동 우회하지 않는다")
    func rejectsInvalidDirectKeys() async {
        for key in ["", "key\r\nInjected: 1"] {
            let client = BookAPIClient(httpClient: HTTPClient(load: { _ in
                Issue.record("유효하지 않은 키로 요청하면 안 됨")
                throw URLError(.badURL)
            }), configuration: { throw APIRelayError.missingAccessToken },
                usesRelay: { _ in false }, providerKey: { _ in key })
            await #expect(throws: APIRelayError.self) {
                try await client.send(.primoSearch, queryItems: [])
            }
        }
    }

    @Test("마이페이지 다섯 번째 연속 입력만 설정을 열고 중단·초기화는 누적하지 않는다")
    func profileTapSequence() {
        var sequence = ProfileTapSequence()
        let first = (0..<6).map { sequence.register(at: Double($0) * 0.1) }
        #expect(first == [false, false, false, false, true, false])
        sequence.reset()
        let paused = [1.0, 1.1, 1.2, 2.0, 2.1, 2.2, 2.3, 2.4].map { sequence.register(at: $0) }
        #expect(paused == [false, false, false, false, false, false, false, true])
        let reversed = [10.0, 10.1, 10.2, 0.0, 0.1, 0.2, 0.3, 0.4].map { sequence.register(at: $0) }
        #expect(reversed == [false, false, false, false, false, false, false, true])
    }
}
