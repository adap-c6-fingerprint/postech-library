import Foundation

nonisolated struct RecommendationCoverResolver: Sendable {
    var data4LibraryLookup: @Sendable (String) async -> URL?
    var isRealImage: @Sendable (URL) async -> Bool

    static func live(
        httpClient: HTTPClient,
        minimumImageBytes: Int,
        configuration: @escaping @Sendable () async throws -> APIRelayConfiguration = {
            try await AppConfiguration.relayConfiguration()
        }
    ) -> Self {
        let api = Data4LibraryAPIClient(relay: .init(httpClient: httpClient, configuration: configuration))
        return Self(
            data4LibraryLookup: { isbn13 in
                try? await api.coverURL(isbn13: isbn13)
            },
            isRealImage: { url in
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                guard let result = try? await httpClient.send(request), result.isSuccessful,
                      result.response.mimeType?.hasPrefix("image/") == true else { return false }
                return result.data.count >= minimumImageBytes
            }
        )
    }
}
