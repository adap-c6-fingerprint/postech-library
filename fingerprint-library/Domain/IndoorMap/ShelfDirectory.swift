import Foundation

/// API의 표시 문자열이나 도서 ID와 구분되는 데이터셋 내부 키.
nonisolated struct ShelfKey: Hashable, Sendable {
    let datasetID: String
    let value: String
}

nonisolated struct ShelfDestination: Equatable, Sendable {
    let key: ShelfKey
    let name: String
    let floorID: UUID
    let mapElementID: IndoorMapElement.ID
    let geometry: IndoorMapGeometry
    let arrivalNodeID: String
    let arrivalCoordinate: IndoorMapCoordinate
}

nonisolated struct ShelfDirectory: Equatable, Sendable {
    enum Mode: String, Decodable, Sendable { case mock, library }

    let datasetID: String
    let mode: Mode
    let destinations: [ShelfDestination]

    func destination(for key: ShelfKey) throws -> ShelfDestination {
        guard key.datasetID == datasetID,
              let destination = destinations.first(where: { $0.key == key }) else {
            throw LookupError.unmappedShelf(key)
        }
        return destination
    }

    enum LookupError: Error, Equatable { case unmappedShelf(ShelfKey) }
}

nonisolated struct IndoorNavigationData: Equatable, Sendable {
    let graph: RoutingGraph
    let shelves: ShelfDirectory
    let diagnostics: RoutingGraphDiagnostics
    var transitionDistances: [String: RouteEdgeDistance] = [:]
}
