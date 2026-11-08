import Foundation
import MapKit

@main
struct ShelfNumberZoomProof {
    static func main() {
        verifyZoomLevels()
        verifyPairedShelfNumbers()
        print("PASS: zoom clustering stops at shelf numbers; A/B source data and highlighting are preserved.")
    }

    private static func verifyZoomLevels() {
        precondition(IndoorShelfLabelLevel.allCases == [.group, .number])
        for previous in [nil, .group, .number] as [IndoorShelfLabelLevel?] {
            for scale in [0.0001, 0.01, 0.049, 0.05, 0.055, 0.06, 0.089] {
                precondition(IndoorShelfLabelLevel.resolve(metersPerPoint: scale, previous: previous) == .number)
            }
            precondition(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.2, previous: previous) == .group)
        }
        // 묶음/개별 번호 전환 경계에서 확대·축소를 반복해도 표시가 흔들리지 않는다.
        precondition(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.1, previous: .group) == .group)
        precondition(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.1, previous: .number) == .number)
        precondition(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.1, previous: nil) == .number)
    }

    private static func verifyPairedShelfNumbers() {
        let thirdFloor = UUID()
        let fourthFloor = UUID()
        let labels = [
            shelf("S-3F-001-A", number: "337", side: .a, floor: thirdFloor, x: 0, y: 0),
            shelf("S-3F-001-B", number: "337", side: .b, floor: thirdFloor, x: 0, y: 0.4),
            shelf("S-3F-002-A", number: "338", side: .a, floor: thirdFloor, x: 2, y: 0),
            shelf("S-3F-002-B", number: "338", side: .b, floor: thirdFloor, x: 2, y: 0.4),
            // 같은 평면 좌표·서가 번호여도 다른 층과 묶이지 않는다.
            shelf("S-4F-001-A", number: "337", side: .a, floor: fourthFloor, x: 0, y: 0),
            shelf("S-4F-001-B", number: "337", side: .b, floor: fourthFloor, x: 0, y: 0.4),
            // 한쪽 면만 있는 서가와 이름으로 표기하는 서가도 보존한다.
            shelf("S-3F-003-A", number: "참고", side: .a, floor: thirdFloor, x: 20, y: 0)
        ]
        let layout = IndoorShelfLabelLayout(labels: labels)
        precondition(layout.numbers.count == 4)
        precondition(Set(layout.numbers.flatMap(\.members).map(\.id)) == Set(labels.map(\.id)))
        precondition(layout.groups.count == 3)
        precondition(layout.groups.contains { $0.floorID == thirdFloor && $0.text == "337~338" })
        precondition(layout.groups.allSatisfy { group in group.members.allSatisfy { $0.floorID == group.floorID } })

        let number = layout.numbers.first { $0.floorID == thirdFloor && $0.text == "337" }!
        precondition(Set(number.members.map(\.side)) == [.a, .b])
        let bounds = number.members.reduce(MKMapRect.null) {
            $0.union(MapKitGeometry.mapRect(for: $1.geometry))
        }
        precondition(abs(number.point.x - bounds.midX) < 0.000001)
        precondition(abs(number.point.y - bounds.midY) < 0.000001)
        precondition(number.isHighlighted(by: [labels[1].mapElementID]))
        precondition(!number.isHighlighted(by: [labels[4].mapElementID]))

        for scale in [0.05, 0.01, 0.0001] {
            let level = IndoorShelfLabelLevel.resolve(metersPerPoint: scale, previous: .number)
            let visible = layout.presentations(at: level)
            precondition(visible.count == 4)
            precondition(visible.allSatisfy { !$0.text.hasSuffix("-A") && !$0.text.hasSuffix("-B") })
            precondition(Set(visible.map(\.text)) == ["337", "338", "참고"])
        }
        let empty = IndoorShelfLabelLayout(labels: [])
        precondition(empty.numbers.isEmpty && empty.groups.isEmpty)
    }

    private static func shelf(_ fixture: String, number: String, side: IndoorShelfLabel.Side,
                              floor: UUID, x: Double, y: Double) -> IndoorShelfLabel {
        let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 36.013, longitude: 129.323))
        let unitsPerMeter = MKMapPointsPerMeterAtLatitude(origin.coordinate.latitude)
        func coordinate(_ dx: Double, _ dy: Double) -> IndoorMapCoordinate {
            let point = MKMapPoint(x: origin.x + (x + dx) * unitsPerMeter,
                                  y: origin.y + (y + dy) * unitsPerMeter).coordinate
            return .init(latitude: point.latitude, longitude: point.longitude)
        }
        return .init(fixtureNumber: fixture, realNumber: number, side: side, sequence: 0,
                     floorID: floor, mapElementID: .init(kind: .fixture, sourceID: UUID()),
                     geometry: .polygon([[coordinate(0, 0), coordinate(1, 0), coordinate(1, 0.3),
                                          coordinate(0, 0.3), coordinate(0, 0)]]), content: .emptyShelf)
    }
}
