import UIKit

enum IndoorMapPalette {
    static let floor = gray(0x35)
    static let furniture = gray(0x55)
    static let wall = gray(0x59)
    static let openSpace = gray(0x20)
    static let privateSpace = gray(0x54)
    static let wallOutline = gray(0x1D)
    static let walkway = gray(0x20)
    static let stairsAndElevator = gray(0x54)
    static let opening = gray(0x62)
    static let restroom = gray(0x55)
    static let relaxZone = gray(0x20)
    static let gameZone = gray(0x20)
    private static let fifthFloorElevatorLobbyID = "732c6ee7-1021-443c-a020-a3ce41460653"

    static func apply(to style: inout IndoorOverlayStyle, feature: IndoorMapElement?, floorOrdinal: Int) {
        style.strokeColor = wallOutline
        guard let feature else {
            style.fillColor = floor
            return
        }
        switch (feature.kind, feature.category?.lowercased()) {
        case (.opening, _):
            style.fillColor = .clear
            style.strokeColor = opening
        case (.unit, "structure"), (.fixture, "wall"):
            style.fillColor = wall
        case (.unit, "stairs"), (.unit, "stairway"), (.unit, "elevator"):
            style.fillColor = stairsAndElevator
        case (.unit, "walkway") where floorOrdinal == 4
            && feature.sourceID.uuidString.lowercased() == fifthFloorElevatorLobbyID:
            style.fillColor = floor
            style.strokeColor = .clear
        case (.unit, "walkway"):
            style.fillColor = walkway
        case (.unit, "opentobelow"):
            style.fillColor = openSpace
        case (.unit, "nonpublic"):
            style.fillColor = privateSpace
        case (.unit, "lounge") where floorOrdinal == 4 && feature.name?.lowercased() == "relax zone":
            style.fillColor = relaxZone
        case (.unit, "recreation"):
            style.fillColor = gameZone
        case (.unit, let category?) where category.hasPrefix("restroom") || category == "toilets":
            style.fillColor = restroom
        case (.fixture, "desk"), (.fixture, "furniture"):
            style.fillColor = furniture
        case (.unit, _), (.section, _):
            style.fillColor = floor
        default:
            break
        }
    }

    private static func gray(_ value: CGFloat) -> UIColor {
        UIColor(red: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }
}
