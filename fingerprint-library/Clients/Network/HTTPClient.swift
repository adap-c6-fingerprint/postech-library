import Foundation

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
        do {
            let (data, response) = try await load(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }
            return HTTPResponse(data: data, response: response)
        } catch {
            try Task.checkCancellation()
            throw error
        }
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
