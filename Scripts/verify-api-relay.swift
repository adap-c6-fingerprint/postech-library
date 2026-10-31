import Foundation

/// Compile with HTTPClient, BookAPIClient, AppConfiguration, PrimoAPIClient and Data4LibraryAPIClient.
/// Reads only the ignored local development token. Never prints credentials or provider payloads.
@main
enum VerifyAPIRelay {
    static func main() async throws {
        let settings = try String(contentsOfFile: "Secrets.xcconfig", encoding: .utf8)
        guard let token = settings.split(separator: "\n").compactMap({ line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "POBOOK_RELAY_TOKEN_DEVELOPMENT" else { return nil }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }).first else { throw APIRelayError.missingAccessToken }
        let relay = BookAPIClient(configuration: { .init(environment: .development, token: token) })
        let primo = try await PrimoAPIClient(relay: relay).search(query: "any,contains,991003794555103286", limit: 1)
        try check(primo, key: "docs")
        let yes24 = try await relay.send(.yes24Detail, queryItems: [
            .init(name: "searchType", value: "ISBN13"), .init(name: "query", value: "9788937460777")
        ])
        try check(yes24, key: "data")
        let data4Library = Data4LibraryAPIClient(relay: relay)
        for endpoint in [Data4LibraryAPIClient.Endpoint.bookDetail, .relatedBooks] {
            try check(try await data4Library.fetch(endpoint, isbn13: "9788937460777"), key: "response")
        }
        print("PASS: application relay client → development HTTPS → four provider routes, HTTP 200 and original JSON envelopes")
    }

    private static func check(_ result: HTTPResponse, key: String) throws {
        guard result.response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              json[key] != nil else { throw HTTPClientError.invalidResponse }
    }
}
