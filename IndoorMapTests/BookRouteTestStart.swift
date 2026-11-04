import Foundation
import Testing
@testable import fingerprint_library

/// 이전 311-B 회귀 사례의 출발 좌표를 테스트에서만 명시적으로 주입한다.
func bookRouteTestStart(on map: IndoorMap, labels: [IndoorShelfLabel]) async throws -> IndoorPosition {
    let destination = try #require(labels.first { $0.fixtureNumber == "S-3F-564-A" })
    return try await BookRoutePreviewTestRouteLoader().load(on: map, labels: labels, destination: destination).start
}
