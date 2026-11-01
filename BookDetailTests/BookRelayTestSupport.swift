import Foundation
@testable import fingerprint_library

extension BookAPIClient {
    nonisolated static func test(load: @escaping HTTPClient.Loader) -> Self {
        Self(httpClient: HTTPClient(load: load), configuration: {
            APIRelayConfiguration(environment: .development, token: "unit-test-relay-token-not-a-provider-key")
        })
    }
}
