import Foundation

nonisolated enum BookCoverFailure: Error, Equatable, Sendable {
    case unavailable(statusCode: Int)
    case invalidResponse
    case httpStatus(Int)
    case invalidImage
    case unreadableLocalFile

    static func validate(data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw Self.invalidResponse
        }
        let status = response.statusCode
        if [204, 404, 410].contains(status) {
            throw Self.unavailable(statusCode: status)
        }
        guard (200..<300).contains(status) else { throw Self.httpStatus(status) }
        let isBlank = data.allSatisfy { [9, 10, 13, 32].contains($0) }
        guard !isBlank else { throw Self.unavailable(statusCode: status) }
    }

    static func isUnavailable(_ error: any Error) -> Bool {
        guard let failure = error as? Self else { return false }
        if case .unavailable = failure { return true }
        return false
    }

    static func isConnectionProblem(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return connectionProblemCodes.contains(error.code)
    }
    // 서버 응답·이미지 문제는 제외하고, 기기가 서버에 닿지 못한 경우만 연결 문제로 본다.

    private static let connectionProblemCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
        .callIsActive
    ]

    struct Diagnostic: Equatable, Sendable {
        let reason: String
        let httpStatus: Int
        let transportCode: Int
    }

    static func diagnostic(for error: any Error) -> Diagnostic {
        if let failure = error as? Self {
            switch failure {
            case let .unavailable(status):
                return Diagnostic(reason: "unavailable", httpStatus: status, transportCode: 0)
            case let .httpStatus(status):
                return Diagnostic(reason: "http", httpStatus: status, transportCode: 0)
            case .invalidResponse:
                return Diagnostic(reason: "response", httpStatus: 0, transportCode: 0)
            case .invalidImage:
                return Diagnostic(reason: "decode", httpStatus: 0, transportCode: 0)
            case .unreadableLocalFile:
                return Diagnostic(reason: "local_file", httpStatus: 0, transportCode: 0)
            }
        }
        return Diagnostic(
            reason: error is URLError ? "transport" : "unknown",
            httpStatus: 0, transportCode: (error as? URLError)?.errorCode ?? 0
        )
    }
}
