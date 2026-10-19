import ComposableArchitecture
import Foundation

nonisolated struct IndoorRouteClient: Sendable {
    var search: @Sendable (IndoorRouteRequest) async throws -> IndoorRouteSearchOutcome

    @concurrent
    private static func calculate(_ request: IndoorRouteRequest) async throws -> IndoorRouteSearchOutcome {
        try Task.checkCancellation()
        let result = try IndoorRouteSearchEngine().search(request)
        try Task.checkCancellation()
        return result
    }
}

extension IndoorRouteClient: DependencyKey {
    static let liveValue = Self(search: calculate)
    static let testValue = Self(search: { _ in throw IndoorRoutingError.noRoute })
}

extension DependencyValues {
    var indoorRouteClient: IndoorRouteClient {
        get { self[IndoorRouteClient.self] }
        set { self[IndoorRouteClient.self] = newValue }
    }
}
