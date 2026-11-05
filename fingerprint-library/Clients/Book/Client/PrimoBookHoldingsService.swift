import Foundation

/// 호출 경계를 주입할 수 있어 동일한 요청·응답 처리를 로컬 HTTP 시뮬레이션에서도 실행한다.
nonisolated struct PrimoBookHoldingsService: Sendable {
    var relay: BookAPIClient = .init()
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    static func isValid(recordID: String) -> Bool {
        recordID.range(of: #"^alma[0-9]{10,30}$"#, options: .regularExpression) != nil
    }

    func fetch(recordID: String) async throws -> [BookHolding] {
        guard Self.isValid(recordID: recordID) else { throw BookHoldingsError.invalidRecordID }
        let api = PrimoAPIClient(relay: relay)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let result: HTTPResponse
            do {
                // POSTECH에서는 rid,exact가 결과를 반환하지 않는다. MMS 검색 후 recordid를 검증한다.
                result = try await api.search(query: "any,contains,\(recordID.dropFirst(4))", timeout: 15)
            } catch {
                try Task.checkCancellation()
                guard Self.isTransientTransportError(error), attempt < 2 else {
                    if error is HTTPClientError { throw BookHoldingsError.invalidResponse }
                    throw error
                }
                try await pauseBeforeRetry(attempt: attempt)
                continue
            }
            try Task.checkCancellation()
            let http = result.response
            if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                guard attempt < 2 else { throw BookHoldingsError.serviceUnavailable }
                // HTTP 오류와 전송 오류가 섞여도 같은 최대 3회 예산을 사용한다.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                guard retryAfter <= 5 else { throw BookHoldingsError.serviceUnavailable }
                try await pauseBeforeRetry(attempt: attempt, minimumDelay: retryAfter)
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw BookHoldingsError.invalidResponse }
            do { return try PrimoHoldingsMapper.decode(result.data, recordID: recordID) }
            catch { throw BookHoldingsError.invalidResponse }
        }
        throw BookHoldingsError.serviceUnavailable
    }

    private func pauseBeforeRetry(attempt: Int, minimumDelay: Double = 0) async throws {
        try Task.checkCancellation()
        try await sleep(.seconds(max(minimumDelay, 0.5 * pow(2, Double(attempt)))))
        try Task.checkCancellation()
    }

    private static func isTransientTransportError(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

}

nonisolated enum BookHoldingsError: LocalizedError {
    case invalidRecordID, invalidResponse, serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRecordID: "이 책의 도서관 자료 번호를 확인할 수 없어요."
        case .invalidResponse, .serviceUnavailable: "도서 위치를 불러오지 못했어요. 다시 시도해 주세요."
        }
    }
}
