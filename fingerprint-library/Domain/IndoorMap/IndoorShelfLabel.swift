import Foundation

/// 지도 도형에 연결한 서가 인덱스. 도착 노드가 없는 상태에서도 표시할 수 있다.
nonisolated struct IndoorShelfLabel: Identifiable, Equatable, Sendable {
    enum Side: String, Decodable, Sendable { case a = "A", b = "B" }
    enum Content: Equatable, Sendable {
        case callNumberRange(start: String, end: String)
        case category(String)
        case emptyShelf
    }

    var id: String { fixtureNumber }
    /// A/B 면을 합친 실제 서가 식별자. 층이 다른 동일 번호는 구분한다.
    ///
    /// 3·4층 fixture는 "...-A"/"...-B"로 면을 나누고, 2층처럼 면 표기가 없는 서가는 이름 전체가 하나다.
    var physicalShelfID: String {
        let base = fixtureNumber.hasSuffix("-\(Side.a.rawValue)") || fixtureNumber.hasSuffix("-\(Side.b.rawValue)")
            ? String(fixtureNumber.dropLast(2)) : fixtureNumber
        return "\(floorID)-\(base)"
    }
    let fixtureNumber: String
    let realNumber: String
    let side: Side
    /// 사진 촬영 순서. 방문 순서나 레이블 우선순위로 사용하지 않는다.
    let sequence: Int
    let floorID: UUID
    let mapElementID: IndoorMapElement.ID
    let geometry: IndoorMapGeometry
    let content: Content

    /// 2층 삼각서가처럼 번호 대신 이름으로 부르는 서가. 면 구분도 없다.
    var isNamedShelf: Bool {
        if case .category = content { true } else { false }
    }
    /// 문장 속 서가 이름. "337번 서가" 또는 "삼각서가 C".
    var shelfTitle: String { isNamedShelf ? realNumber : "\(realNumber)번 서가" }
    /// 면까지 구분한 서가 표기. "337-A" 또는 "삼각서가 C".
    var faceTitle: String { isNamedShelf ? realNumber : "\(realNumber)-\(side.rawValue)" }
}
