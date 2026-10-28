import Foundation

nonisolated struct RoutingGraphDTO: Decodable {
    let type: String
    let schemaVersion: Int
    let layoutVersion: String
    let routingConfig: Configuration
    let features: [Feature]

    enum CodingKeys: String, CodingKey {
        case type, features
        case schemaVersion = "schema_version"
        case layoutVersion = "layout_version"
        case routingConfig = "routing_config"
    }

    struct Configuration: Decodable {
        let hardSearchRadiusMeters: Double
        enum CodingKeys: String, CodingKey { case hardSearchRadiusMeters = "hard_search_radius_meters" }
    }

    struct Feature: Decodable {
        let type: String
        let id: String
        let properties: Properties
        let geometry: IMDFGeometryDTO
    }

    struct Properties: Decodable {
        let role: String
        let level: Int?
        let levelID: UUID?
        let name: String?
        let category: String?
        let from: String?
        let to: String?
        let direction: RouteEdgeDirection?
        let accessible: Bool?
        let traversalSeconds: Double?
        var groupID: UUID? = nil

        enum CodingKeys: String, CodingKey {
            case role, level, name, category, from, to, direction, accessible
            case levelID = "level_id"
            case traversalSeconds = "traversal_seconds"
            case groupID = "group_id"
        }
    }
}

nonisolated struct ShelfDirectoryDTO: Decodable {
    let schemaVersion: Int
    let datasetID: String
    let layoutVersion: String
    let mode: ShelfDirectory.Mode
    let shelves: [Shelf]

    enum CodingKeys: String, CodingKey {
        case mode, shelves
        case schemaVersion = "schema_version"
        case datasetID = "dataset_id"
        case layoutVersion = "layout_version"
    }

    struct Shelf: Decodable {
        let key: String
        let name: String
        let floorID: UUID
        let elementKind: String
        let elementID: UUID
        let arrivalNodeID: String

        enum CodingKeys: String, CodingKey {
            case key, name
            case floorID = "level_id"
            case elementKind = "element_kind"
            case elementID = "element_id"
            case arrivalNodeID = "arrival_node_id"
        }
    }
}
