import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationLibraryGuidanceTests {
    @Test("실제 번들 도서관 경로를 1.5m 간격으로 이동하면 안내가 이어지고 남은 거리가 감소한다")
    func followsBundledRoute() async throws {
        #if NAVIGATION_VALIDATION
        let directory = try #require(Bundle.module.url(forResource: "POSTECHLibrary", withExtension: nil))
        #else
        let directory = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
            .appendingPathComponent("POSTECHLibrary")
        #endif
        let map = try await BundledIndoorMapLoader().load(directory: directory.appendingPathComponent("IMDFData"))
        let labels = try BundledShelfLabelLoader().decode(Data(contentsOf: directory.appendingPathComponent("shelfdata.json")), on: map)
        let goal = try #require(labels.first { $0.fixtureNumber == "S-3F-564-A" })
        let input = try await BookRoutePreviewTestRouteLoader().load(directory: directory, on: map, labels: labels, destination: goal)
        let plan = try RouteGuidancePlan(route: input.route, graph: input.graph)
        var previous: RouteGuidanceProgress?
        var sampleCount = 0
        var maneuvers = Set<String>()
        for segment in input.route.segments {
            let floor = try #require(map.floors.first { $0.id == segment.floorID })
            for (a, b) in zip(segment.coordinates, segment.coordinates.dropFirst()) {
                let count = max(1, Int(ceil(RoutingGeometry.distanceMeters(from: a, to: b) / 1.5)))
                for sample in 0...count {
                    let fraction = Double(sample) / Double(count)
                    let position = IndoorPosition(coordinate: .init(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                        longitude: a.longitude + (b.longitude - a.longitude) * fraction),
                        floorOrdinal: floor.ordinal, horizontalAccuracy: 0,
                        timestamp: NavigationGuidanceTestFixture.now.addingTimeInterval(Double(sampleCount)), source: .replay)
                    let progress = try plan.progress(for: position, at: position.timestamp, previous: previous, elapsed: 1)
                    if let old = previous?.remainingMeters, let current = progress.remainingMeters {
                        #expect(current <= old + 0.02)
                    }
                    maneuvers.insert(String(describing: progress.maneuver))
                    previous = progress
                    sampleCount += 1
                }
            }
        }
        #expect(sampleCount > 10)
        #expect(previous?.maneuver == .nearDestination)
        #expect(abs(previous?.remainingMeters ?? .infinity) < 0.1)
        print("Bundled guidance replay: \(sampleCount) positions, \(maneuvers.count) maneuver states, route \(input.route.distanceMeters)m")
    }
}
