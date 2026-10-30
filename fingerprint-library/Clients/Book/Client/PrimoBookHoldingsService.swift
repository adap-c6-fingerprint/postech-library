import Foundation

/// 호출 경계를 주입할 수 있어 동일한 요청·응답 처리를 로컬 HTTP 시뮬레이션에서도 실행한다.
nonisolated struct PrimoBookHoldingsService: Sendable {
    var baseURL: URL
    var apiKey: String?
    var httpClient: HTTPClient

    init(
        baseURL: URL = PrimoAPIClient.defaultBaseURL,
        apiKey: String? = nil,
        httpClient: HTTPClient = .urlSession()
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    init(baseURL: URL = PrimoAPIClient.defaultBaseURL, apiKey: String? = nil, session: URLSession) {
        self.init(baseURL: baseURL, apiKey: apiKey, httpClient: .urlSession(session))
    }

    static func isValid(recordID: String) -> Bool {
        recordID.range(of: #"^alma[0-9]{10,30}$"#, options: .regularExpression) != nil
    }

    func fetch(recordID: String) async throws -> [BookHolding] {
        guard Self.isValid(recordID: recordID) else { throw BookHoldingsError.invalidRecordID }
        let api = PrimoAPIClient(httpClient: httpClient, baseURL: baseURL, apiKey: apiKey)
        for attempt in 0..<3 {
            let result: HTTPResponse
            do {
                // POSTECH에서는 rid,exact가 결과를 반환하지 않는다. MMS 검색 후 recordid를 검증한다.
                result = try await api.search(query: "any,contains,\(recordID.dropFirst(4))", timeout: 15)
            } catch is HTTPClientError {
                throw BookHoldingsError.invalidResponse
            }
            let http = result.response
            if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                guard attempt < 2 else { throw BookHoldingsError.serviceUnavailable }
                // 호출 화면에서 동시 요청을 제한한다. 재시도는 0.5초·1초 간격이다.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                guard retryAfter <= 5 else { throw BookHoldingsError.serviceUnavailable }
                try await Task.sleep(for: .seconds(max(retryAfter, 0.5 * pow(2, Double(attempt)))))
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw BookHoldingsError.invalidResponse }
            do { return try PrimoHoldingsMapper.decode(result.data, recordID: recordID) }
            catch { throw BookHoldingsError.invalidResponse }
        }
        throw BookHoldingsError.serviceUnavailable
    }
}

nonisolated enum BookHoldingsError: LocalizedError {
    case missingAPIKey, missingProxy, invalidProxyURL, invalidRecordID, invalidResponse, serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "도서 위치 조회를 위한 API 키가 설정되지 않았어요."
        case .missingProxy, .invalidProxyURL: "도서 위치 조회 서버가 설정되지 않았어요."
        case .invalidRecordID: "이 책의 도서관 자료 번호를 확인할 수 없어요."
        case .invalidResponse, .serviceUnavailable: "도서 위치를 불러오지 못했어요. 다시 시도해 주세요."
        }
    }
}
