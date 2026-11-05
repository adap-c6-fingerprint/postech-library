import Foundation

nonisolated enum APIRelayEnvironment: String, Sendable {
    case development = "DEVELOPMENT"
    case testFlight = "TESTFLIGHT"
    case production = "PRODUCTION"

    enum Distribution: Sendable { case xcode, sandbox, production }

    var baseURL: URL {
        switch self {
        case .development: URL(string: "https://pobook-api-dev.fpmaps.com")!
        case .testFlight: URL(string: "https://pobook-api-testfligh.fpmaps.com")!
        case .production: URL(string: "https://pobook-api.fpmaps.com")!
        }
    }

    static func select(internalBuild: Bool, distribution: Distribution?) throws -> Self {
        if internalBuild { return .development }
        switch distribution {
        case .xcode: return .development
        case .sandbox: return .testFlight
        case .production: return .production
        case nil: throw APIRelayError.unknownDistribution
        }
    }
}

nonisolated struct APIRelayConfiguration: Sendable {
    var environment: APIRelayEnvironment
    var token: String
}

/// 도서 API 경로만 선택한다. 이미지 다운로드와 공급자별 응답 해석은 변경하지 않는다.
nonisolated struct BookAPIClient: Sendable {
    enum Endpoint: String, Sendable {
        case primoSearch = "primo/v1/search"
        case yes24Detail = "yes24/v1/goods/itemDetail"
        case data4LibraryDetail = "data4library/api/srchDtlList"
        case data4LibraryRelated = "data4library/api/recommandList"

        var provider: BookAPIProvider {
            switch self {
            case .primoSearch: .primo
            case .yes24Detail: .yes24
            case .data4LibraryDetail, .data4LibraryRelated: .data4Library
            }
        }

        var directURL: URL {
            switch self {
            case .primoSearch: URL(string: "https://api-ap.hosted.exlibrisgroup.com/primo/v1/search")!
            case .yes24Detail: URL(string: "https://apis.yes24.com/v1/goods/itemDetail")!
            case .data4LibraryDetail: URL(string: "https://data4library.kr/api/srchDtlList")!
            case .data4LibraryRelated: URL(string: "https://data4library.kr/api/recommandList")!
            }
        }
    }

    var httpClient: HTTPClient = .urlSession()
    var configuration: @Sendable () async throws -> APIRelayConfiguration = {
        try await AppConfiguration.relayConfiguration()
    }
    var usesRelay: @Sendable (Endpoint) -> Bool = {
        APIRoutingSettings.load()[$0.provider]
    }
    var providerKey: @Sendable (BookAPIProvider) throws -> String = {
        try AppConfiguration.providerAPIKey(for: $0)
    }

    func send(_ endpoint: Endpoint, queryItems: [URLQueryItem], timeout: TimeInterval = 60) async throws -> HTTPResponse {
        try Task.checkCancellation()
        guard !queryItems.contains(where: { ["apikey", "authkey"].contains($0.name.lowercased()) }) else {
            throw APIRelayError.providerCredentialNotAllowed
        }
        if !usesRelay(endpoint) {
            return try await sendDirect(endpoint, queryItems: queryItems, timeout: timeout)
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

    private func sendDirect(_ endpoint: Endpoint, queryItems: [URLQueryItem], timeout: TimeInterval) async throws -> HTTPResponse {
        let key = try providerKey(endpoint.provider)
        guard !key.isEmpty, key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw APIRelayError.missingProviderKey
        }
        var components = URLComponents(url: endpoint.directURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        if endpoint.provider == .data4Library {
            components?.queryItems?.append(URLQueryItem(name: "authKey", value: key))
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // 정보나루는 application/json Accept 요청에 406을 반환한다.
        request.setValue(endpoint.provider == .data4Library ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        switch endpoint.provider {
        case .primo: request.setValue("apikey \(key)", forHTTPHeaderField: "Authorization")
        case .yes24: request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        case .data4Library: break
        }
        return try await httpClient.send(request)
    }
}

nonisolated enum APIRelayError: LocalizedError {
    case unknownDistribution, missingAccessToken, invalidBuildChannel, providerCredentialNotAllowed
    case missingProviderKey

    var errorDescription: String? {
        switch self {
        case .unknownDistribution: "앱 배포 환경을 확인하지 못했어요. 다시 시도해 주세요."
        case .missingAccessToken: "이 빌드의 도서 API 서버 접근 설정이 필요해요."
        case .invalidBuildChannel: "앱 빌드 환경 설정을 확인해 주세요."
        case .providerCredentialNotAllowed: "도서 API 인증 요청 설정을 확인해 주세요."
        case .missingProviderKey: "이 빌드의 직접 호출용 API 키 설정이 필요해요."
        }
    }
}
