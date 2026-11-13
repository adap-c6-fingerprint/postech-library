import MapKit
import Testing
import UIKit
@testable import fingerprint_library

@MainActor
struct IndoorOverlayBatcherTests {
    private let shelf = IndoorOverlayStyle(fillColor: .brown, strokeColor: .black, lineWidth: 1)
    private let floor = IndoorOverlayStyle(fillColor: .gray, strokeColor: .black, lineWidth: 1)

    @Test func 같은_스타일이_이어지는_도형은_하나의_overlay로_묶는다() throws {
        var batcher = IndoorOverlayBatcher()
        for index in 0..<3 { batcher.append(square(at: index), style: shelf) }

        let batches = batcher.finish()

        #expect(batches.count == 1)
        let multi = try #require(batches.first?.overlay as? MKMultiPolygon)
        #expect(multi.polygons.count == 3)
        #expect(batches.first?.style == shelf)
    }

    @Test func 스타일이_바뀌면_그리기_순서를_유지하며_나눈다() {
        var batcher = IndoorOverlayBatcher()
        batcher.append(square(at: 0), style: floor)
        batcher.append(square(at: 1), style: floor)
        batcher.append(square(at: 2), style: shelf)
        batcher.append(square(at: 3), style: floor)

        let batches = batcher.finish()

        #expect(batches.map(\.style) == [floor, shelf, floor])
        #expect((batches[0].overlay as? MKMultiPolygon)?.polygons.count == 2)
        #expect(batches[1].overlay is MKPolygon)
        #expect(batches[2].overlay is MKPolygon)
    }

    @Test func 선_도형은_면_도형과_따로_묶는다() throws {
        var batcher = IndoorOverlayBatcher()
        batcher.append(.lineString([coordinate(0, 0), coordinate(0, 1)]), style: floor)
        batcher.append(.lineString([coordinate(1, 0), coordinate(1, 1)]), style: floor)
        batcher.append(.point(coordinate(0, 0)), style: shelf)

        let batches = batcher.finish()

        #expect(batches.count == 1)
        let multi = try #require(batches.first?.overlay as? MKMultiPolyline)
        #expect(multi.polylines.count == 2)
    }

    @Test func 여러_조각으로_된_도형은_조각을_모두_포함한다() throws {
        var batcher = IndoorOverlayBatcher()
        let parts = [0, 1].map { index in ring(at: index) }
        batcher.append(.multiPolygon(parts.map { [$0] }), style: shelf)
        batcher.append(square(at: 2), style: shelf)

        let batches = batcher.finish()

        let multi = try #require(batches.first?.overlay as? MKMultiPolygon)
        #expect(batches.count == 1)
        #expect(multi.polygons.count == 3)
    }

    private func square(at index: Int) -> IndoorMapGeometry {
        .polygon([ring(at: index)])
    }

    private func ring(at index: Int) -> [IndoorMapCoordinate] {
        let x = Double(index) * 0.001
        return [coordinate(x, 0), coordinate(x + 0.0005, 0), coordinate(x + 0.0005, 0.0005), coordinate(x, 0.0005), coordinate(x, 0)]
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) -> IndoorMapCoordinate {
        IndoorMapCoordinate(latitude: 36 + latitude, longitude: 129 + longitude)
    }
}
