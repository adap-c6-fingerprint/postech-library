import ComposableArchitecture
import Foundation

extension HTTPClient: DependencyKey {
    static let liveValue = Self.urlSession()
    static let testValue = Self(load: { _ in throw URLError(.unsupportedURL) })
}

extension DependencyValues {
    nonisolated var httpClient: HTTPClient {
        get { self[HTTPClient.self] }
        set { self[HTTPClient.self] = newValue }
    }
}
