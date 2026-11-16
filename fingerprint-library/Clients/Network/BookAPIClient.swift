import Foundation

nonisolated enum APIRelayEnvironment: String, Sendable {
    case development = "DEVELOPMENT"
    case production = "PRODUCTION"
    
    var baseURL: URL {
        switch self {
        case .development: URL(string: "https://pobook-api-dev.fpmaps.com")!
        case .production: URL(string: "https://pobook-api.fpmaps.com")!
        }
    }
}

nonisolated struct APIRelayConfiguration: Sendable {
    var environment: APIRelayEnvironment
    var token: String
}

nonisolated struct BookAPIClient: Sendable {
    enum Endpoint: String, Sendable {
        case primoSearch = "primo/v1/search"
        case yes24Detail = "yes24/v1/goods/itemDetail"
        case data4LibraryDetail = "data4library/api/srchDtlList"
        case data4LibraryRelated = "data4library/api/recommandList"
    }
    
    var httpClient: HTTPClient = .urlSession()
    var configuration: @Sendable () async throws -> APIRelayConfiguration = {
        try AppConfiguration.relayConfiguration()
    }
    
    func send(_ endpoint: Endpoint, queryItems: [URLQueryItem], timeout: TimeInterval = 60) async throws -> HTTPResponse {
        try Task.checkCancellation()
        guard !queryItems.contains(where: { ["apikey", "authkey"].contains($0.name.lowercased()) }) else {
            throw APIRelayError.providerCredentialNotAllowed
        }
        let config = try await configuration()
        try Task.checkCancellation()
        guard config.token.count >= 32, config.token.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw APIRelayError.missingAccessToken
        }
        var components = URLComponents(url: config.environment.baseURL.appending(path: endpoint.rawValue), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        return try await httpClient.send(request)
    }
}

nonisolated enum APIRelayError: LocalizedError {
    case missingAccessToken, invalidBuildChannel, providerCredentialNotAllowed

    var errorDescription: String? {
        switch self {
        case .missingAccessToken: "이 빌드의 도서 API 서버 접근 설정이 필요해요."
        case .invalidBuildChannel: "앱 빌드 환경 설정을 확인해 주세요."
        case .providerCredentialNotAllowed: "도서 API 인증 요청 설정을 확인해 주세요."
        }
    }
}

