//
//  RoutePlanningClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/30/26.
//

import ComposableArchitecture

/// 책과 서가 후보, 출발 위치로 경로 계획을 만든다.
///
/// 길찾기 자료 조회는 RoutePlanningLoader가, 방문 순서·서가 선택 계산은 Domain의 RoutePlanner가 맡는다.
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
