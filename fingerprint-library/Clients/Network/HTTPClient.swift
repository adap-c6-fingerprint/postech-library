import Foundation

/// API별 인증·상태 코드 정책과 분리한 공통 HTTP 전송 경계.
nonisolated struct HTTPClient: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Loader

    init(load: @escaping Loader) {
        self.load = load
    }

    static func urlSession(_ session: URLSession = .shared) -> Self {
        Self(load: { try await session.data(for: $0) })
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try Task.checkCancellation()
        let (data, response) = try await load(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        // 404의 상품 없음, 429의 재시도 등은 각 API에서 본문·헤더와 함께 해석한다.
        return HTTPResponse(data: data, response: response)
    }
}

nonisolated struct HTTPResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse

    var isSuccessful: Bool { (200..<300).contains(response.statusCode) }
}

nonisolated enum HTTPClientError: Error {
    case invalidResponse
}
