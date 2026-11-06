import Foundation

/// 실제 HTTPClient를 로컬 HTTP에 연결해 전송 전 목적지·인증과 응답을 검증한다.
@main
enum VerifyAppStoreAPIRouting {
    static let relayToken = "local-proof-relay-token-with-at-least-32-characters"
    static let primoKey = "local-proof-primo-key"
    static let isbn = "9788937460777"

    static func main() async throws {
        let base = URL(string: CommandLine.arguments.dropFirst().first ?? "http://127.0.0.1:47585")!
        // 기존 사용자가 저장한 값과 반대인 경로도 고정 정책을 바꾸지 못해야 한다.
        UserDefaults.standard.setVolatileDomain([
            "apiRouting.primo.usesRelay": true,
            "apiRouting.yes24.usesRelay": false,
            "apiRouting.data4Library.usesRelay": false
        ], forName: UserDefaults.argumentDomain)
        let recorder = Recorder()
        let direct = BookAPIClient(httpClient: transport(base: base, environment: nil, recorder: recorder), configuration: {
            throw Failure(message: "Primo requested relay configuration")
        }, primoAPIKey: { primoKey })
        let primo = try await PrimoAPIClient(relay: direct).search(query: "any,contains,991000958759703286", limit: 1)
        let primoJSON = try JSONSerialization.jsonObject(with: primo.data) as? [String: Any]
        try check(primo.isSuccessful && (primoJSON?["docs"] as? [Any])?.count == 1,
                  "Primo direct request did not preserve the response")

        for environment in [APIRelayEnvironment.development, .testFlight, .production] {
            let relay = BookAPIClient(httpClient: transport(base: base, environment: environment, recorder: recorder), configuration: {
                .init(environment: environment, token: relayToken)
            }, primoAPIKey: { throw Failure(message: "Relay requested Primo key") })
            let yes24 = try await relay.send(.yes24Detail, queryItems: [
                .init(name: "searchType", value: "ISBN13"), .init(name: "query", value: isbn)
            ], timeout: 15)
            let yes24JSON = try JSONSerialization.jsonObject(with: yes24.data) as? [String: Any]
            try check(yes24.isSuccessful && yes24JSON?["data"] != nil, "Yes24 relay envelope")
            let data4Library = Data4LibraryAPIClient(relay: relay)
            let cover = try await data4Library.coverURL(isbn13: isbn)
            try check(cover?.host == "image.yes24.com", "Data4Library detail envelope")
            let related = try await data4Library.fetch(.relatedBooks, isbn13: isbn)
            let relatedJSON = try JSONSerialization.jsonObject(with: related.data) as? [String: Any]
            try check(related.isSuccessful && relatedJSON?["response"] != nil, "Data4Library related envelope")
        }
        let failingRelay = BookAPIClient(httpClient: transport(base: base, environment: .development, recorder: recorder), configuration: {
            .init(environment: .development, token: relayToken)
        }, primoAPIKey: { throw Failure(message: "Relay fallback requested provider key") })
        let failed = try await failingRelay.send(.yes24Detail, queryItems: [
            .init(name: "searchType", value: "ISBN13"), .init(name: "query", value: "9788931022728")
        ])
        try check(failed.response.statusCode == 503, "Relay 503 must not fall back to direct API")

        for endpoint in [BookAPIClient.Endpoint.primoSearch, .yes24Detail, .data4LibraryDetail, .data4LibraryRelated] {
            do {
                _ = try await failingRelay.send(endpoint, queryItems: [.init(name: "authKey", value: "must-not-be-sent")])
                throw Failure(message: "Provider credential query accepted")
            } catch APIRelayError.providerCredentialNotAllowed { }
        }
        let missingKey = BookAPIClient(httpClient: transport(base: base, environment: nil, recorder: recorder), configuration: {
            throw Failure(message: "Primo key failure requested relay")
        }, primoAPIKey: { "" })
        do {
            _ = try await missingKey.send(.primoSearch, queryItems: [])
            throw Failure(message: "Empty Primo key accepted")
        } catch APIRelayError.missingPrimoAPIKey { }
        let missingToken = BookAPIClient(httpClient: transport(base: base, environment: .development, recorder: recorder), configuration: {
            .init(environment: .development, token: "")
        }, primoAPIKey: { throw Failure(message: "Missing relay token fell back to provider key") })
        do {
            _ = try await missingToken.send(.yes24Detail, queryItems: [])
            throw Failure(message: "Empty relay token accepted")
        } catch APIRelayError.missingAccessToken { }

        try check(await recorder.count == 11, "Unexpected HTTP request or fallback")
        let (countsData, _) = try await URLSession.shared.data(from: base.appending(path: "relay/__counts"))
        let counts = try JSONDecoder().decode([String: Int].self, from: countsData)
        try check(counts == ["/yes24/v1/goods/itemDetail": 4, "/data4library/api/srchDtlList": 3,
                             "/data4library/api/recommandList": 3], "Relay HTTP counts")
        print("PASS: Primo direct without relay configuration; Yes24/Data4Library relay across 3 environments; legacy preferences ignored; credentials isolated; 503 and missing credentials cause no direct fallback")
    }

    static func transport(base: URL, environment: APIRelayEnvironment?, recorder: Recorder) -> HTTPClient {
        HTTPClient(load: { original in
            guard let url = original.url else { throw Failure(message: "Missing request URL") }
            let direct = url.host == "api-ap.hosted.exlibrisgroup.com"
            if direct {
                try check(environment == nil && url.path == "/primo/v1/search", "Wrong direct API destination")
                try check(original.value(forHTTPHeaderField: "Authorization") == "apikey \(primoKey)", "Primo authentication")
            } else {
                try check(url.host == environment?.baseURL.host && url.path != "/primo/v1/search", "Wrong relay destination")
                try check(original.value(forHTTPHeaderField: "Authorization") == "Bearer \(relayToken)", "Relay authentication")
            }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            try check(!query.contains { ["apikey", "authkey"].contains($0.name.lowercased()) }, "Provider key leaked into URL")
            try check(original.value(forHTTPHeaderField: "X-Api-Key") == nil, "Provider key leaked into relay header")
            try check(original.value(forHTTPHeaderField: "Accept") == "application/json", "JSON Accept header")
            var target = URLComponents(url: base.appending(path: direct ? "library" : "relay").appending(path: url.path),
                                       resolvingAgainstBaseURL: false)!
            target.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            var request = original
            request.url = target.url
            await recorder.record()
            return try await URLSession.shared.data(for: request)
        })
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
    actor Recorder {
        private(set) var count = 0
        func record() { count += 1 }
    }
}
