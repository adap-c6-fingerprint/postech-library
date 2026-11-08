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
    var physicalShelfID: String { "\(floorID)-\(fixtureNumber.dropLast(2))" }
    let fixtureNumber: String
    let realNumber: String
    let side: Side
    /// 사진 촬영 순서. 방문 순서나 레이블 우선순위로 사용하지 않는다.
    let sequence: Int
    let floorID: UUID
    let mapElementID: IndoorMapElement.ID
    let geometry: IndoorMapGeometry
    let content: Content
}
