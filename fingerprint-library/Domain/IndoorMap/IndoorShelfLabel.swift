import Foundation

nonisolated struct IndoorShelfLabel: Identifiable, Equatable, Sendable {
    enum Side: String, Decodable, Sendable { case a = "A", b = "B" }
    enum Content: Equatable, Sendable {
        case callNumberRange(start: String, end: String)
        case category(String)
        case emptyShelf
    }

    var id: String { fixtureNumber }
    var physicalShelfID: String {
        let base = fixtureNumber.hasSuffix("-\(Side.a.rawValue)") || fixtureNumber.hasSuffix("-\(Side.b.rawValue)")
            ? String(fixtureNumber.dropLast(2)) : fixtureNumber
        return "\(floorID)-\(base)"
    }
    let fixtureNumber: String
    let realNumber: String
    let side: Side
    let sequence: Int
    let floorID: UUID
    let mapElementID: IndoorMapElement.ID
    let geometry: IndoorMapGeometry
    let content: Content

    var isNamedShelf: Bool {
        if case .category = content { true } else { false }
    }
    var shelfTitle: String { isNamedShelf ? realNumber : "\(realNumber)번 서가" }
    var faceTitle: String { isNamedShelf ? realNumber : "\(realNumber)-\(side.rawValue)" }
}
