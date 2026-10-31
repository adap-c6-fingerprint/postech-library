//
//  BookRoutePreviewClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/30/26.
//

import ComposableArchitecture

nonisolated struct BookRoutePreviewClient: Sendable {
    var load: @Sendable (
        IndoorMap,
        [IndoorShelfLabel],
        [BookNavigationStop]
    ) async throws -> BookNavigationSession
}

extension BookRoutePreviewClient: DependencyKey {
    static let liveValue = BookRoutePreviewClient(
        load: { map, labels, stops in
            try await BookRoutePreviewTestRouteLoader().load(
                on: map,
                labels: labels,
                stops: stops
            )
        }
    )
    
    static let testValue = BookRoutePreviewClient(
        load: { _, _, _ in
            throw IndoorRoutingError.noRoute
        }
    )
}

extension DependencyValues {
    var bookRoutePreviewClient: BookRoutePreviewClient {
        get { self[BookRoutePreviewClient.self] }
        set { self[BookRoutePreviewClient.self] = newValue }
    }
}
