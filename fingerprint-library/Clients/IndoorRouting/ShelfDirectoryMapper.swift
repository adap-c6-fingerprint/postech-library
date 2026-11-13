import Foundation

nonisolated struct ShelfDirectoryMapper {
    func map(_ dto: ShelfDirectoryDTO, on map: IndoorMap, graph: RoutingGraph, datasetID: String) throws -> ShelfDirectory {
        guard dto.schemaVersion == 1, dto.datasetID == datasetID,
              !datasetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dto.layoutVersion == graph.layoutVersion else {
            throw invalid("schema·데이터셋·layout_version이 일치하지 않습니다.")
        }
        let elements = Dictionary(uniqueKeysWithValues: map.features.map { ($0.id, $0) })
        let floors = Dictionary(uniqueKeysWithValues: map.floors.map { ($0.id, $0) })
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var keys = Set<String>()
        let destinations = try dto.shelves.map { shelf in
            guard !shelf.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  keys.insert(shelf.key).inserted,
                  !shelf.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let kind = IndoorMapElement.Kind(rawValue: shelf.elementKind), [.unit, .fixture].contains(kind),
                  let element = elements[.init(kind: kind, sourceID: shelf.elementID)],
                  let floor = floors[shelf.floorID], element.floorID == floor.id,
                  let node = nodes[shelf.arrivalNodeID], node.floorID == floor.id,
                  floor.geometry.contains(node.coordinate) else {
                throw invalid("서가 키·도형·층·도착 노드를 확인하세요: \(shelf.key)")
            }
            return ShelfDestination(key: .init(datasetID: datasetID, value: shelf.key), name: shelf.name,
                                    floorID: floor.id, mapElementID: element.id, geometry: element.geometry,
                                    arrivalNodeID: node.id, arrivalCoordinate: node.coordinate)
        }
        guard !destinations.isEmpty else { throw invalid("서가 매핑이 비어 있습니다.") }
        return ShelfDirectory(datasetID: datasetID, mode: dto.mode, destinations: destinations)
    }

    private func invalid(_ reason: String) -> IndoorMapLoadError {
        .invalidData(file: "shelves.json", reason: reason)
    }
}
