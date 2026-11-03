import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorShelfLabelLevelsTests {
    @Test("실제 A/B 308면은 번호 154개가 되고 가까운 서가 군집에서만 범위를 표시한다")
    func groupsPhysicalShelves() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let layout = IndoorShelfLabelLayout(labels: labels)
        #expect(layout.sides.count == 308)
        #expect(layout.numbers.count == 154)
        #expect(layout.groups.count < layout.numbers.count)
        #expect(layout.numbers.allSatisfy { $0.members.count == 2 && !$0.text.contains("-") })
        #expect(Set(layout.groups.flatMap { $0.members.map(\.id) }) == Set(labels.map(\.id)))
        #expect(layout.groups.allSatisfy { Set($0.members.map(\.floorID)).count == 1 })
        let firstGroup = try #require(layout.groups.first { $0.text == "301~310" })
        #expect(firstGroup.members.count == 20)
        let centers = layout.numbers.filter { $0.members.contains { $0.realNumber == "301" || $0.realNumber == "310" } }
        #expect(centers.allSatisfy { $0.point.distance(to: firstGroup.point) < 15 })
        #expect(layout.numbers.contains { $0.text == "499A" })
        #expect(layout.sides.contains { $0.text == "499A-A" })
        for side in layout.sides {
            let p = side.coordinate
            #expect(side.members[0].geometry.contains(.init(latitude: p.latitude, longitude: p.longitude)))
        }
        // 대표 레이블이 바뀌어도 길찾기에서 사용할 원본 식별자와 A/B 내용은 유지한다.
        #expect(layout.sides.map { $0.members[0] }.sorted { $0.id < $1.id } == labels.sorted { $0.id < $1.id })
        #expect(IndoorShelfLabelLayout(labels: []).groups.isEmpty)
    }

    @Test("단계 경계의 작은 확대 흔들림에는 번호가 반복 전환되지 않는다")
    func stabilizesZoomBoundaries() {
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.5, previous: nil) == .group)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.1, previous: nil) == .number)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.03, previous: nil) == .side)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.095, previous: .group) == .group)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.105, previous: .number) == .number)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.052, previous: .number) == .number)
        #expect(IndoorShelfLabelLevel.resolve(metersPerPoint: 0.058, previous: .side) == .side)
    }

}
