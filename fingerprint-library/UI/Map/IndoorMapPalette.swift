import MapKit
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

    static func apply(to renderer: MKOverlayPathRenderer, feature: IndoorMapElement?, floorOrdinal: Int) {
        renderer.strokeColor = wallOutline
        guard let feature else {
            renderer.fillColor = floor
            return
        }
        switch (feature.kind, feature.category?.lowercased()) {
        case (.opening, _):
            renderer.fillColor = .clear
            renderer.strokeColor = opening
        case (.unit, "structure"), (.fixture, "wall"):
            renderer.fillColor = wall
        case (.unit, "stairs"), (.unit, "stairway"), (.unit, "elevator"):
            renderer.fillColor = stairsAndElevator
        case (.unit, "walkway") where floorOrdinal == 4
            && feature.sourceID.uuidString.lowercased() == fifthFloorElevatorLobbyID:
            renderer.fillColor = floor
            renderer.strokeColor = .clear
        case (.unit, "walkway"):
            renderer.fillColor = walkway
        case (.unit, "opentobelow"):
            renderer.fillColor = openSpace
        case (.unit, "nonpublic"):
            renderer.fillColor = privateSpace
        case (.unit, "lounge") where floorOrdinal == 4 && feature.name?.lowercased() == "relax zone":
            renderer.fillColor = relaxZone
        case (.unit, "recreation"):
            renderer.fillColor = gameZone
        case (.unit, let category?) where category.hasPrefix("restroom") || category == "toilets":
            renderer.fillColor = restroom
        case (.fixture, "desk"), (.fixture, "furniture"):
            renderer.fillColor = furniture
        case (.unit, _), (.section, _):
            renderer.fillColor = floor
        default:
            break
        }
    }

    private static func gray(_ value: CGFloat) -> UIColor {
        UIColor(red: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }
}
