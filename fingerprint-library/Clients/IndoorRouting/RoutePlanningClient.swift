//
//  RoutePlanningClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/30/26.
//

import ComposableArchitecture

nonisolated struct RoutePlanningClient: Sendable {
    var plan: @Sendable (
        IndoorMap,
        [IndoorShelfLabel],
        IndoorPosition,
        [RouteCandidateStop]
    ) async throws -> RoutePlan
}

extension RoutePlanningClient: DependencyKey {
    static let liveValue = RoutePlanningClient(
        plan: { map, labels, start, stops in
            try await RoutePlanningLoader().load(
                on: map,
                labels: labels,
                start: start,
                stops: stops
            )
        }
    )
    
    static let testValue = RoutePlanningClient(
        plan: { _, _, _, _ in
            throw IndoorRoutingError.noRoute
        }
    )
}

nonisolated extension DependencyValues {
    var routePlanningClient: RoutePlanningClient {
        get { self[RoutePlanningClient.self] }
        set { self[RoutePlanningClient.self] = newValue }
    }
}
