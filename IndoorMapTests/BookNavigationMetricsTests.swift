import Testing
@testable import fingerprint_library

struct BookNavigationMetricsTests {
    @Test("시간·걸음은 남은 거리로 계산하며 안내 단계 수를 보행 걸음 수로 쓰지 않는다")
    func estimatesWalking() throws {
        let normal = try #require(BookNavigationMetrics(remainingMeters: 100))
        #expect(normal.minutes == 1 && normal.steps == 143)
        let nearby = try #require(BookNavigationMetrics(remainingMeters: 8))
        #expect(nearby.minutes == 0 && nearby.steps == 12)
        #expect(BookNavigationMetrics(remainingMeters: 0)?.steps == 0)
    }

    @Test("유효하지 않거나 정수 범위를 초과하는 거리는 크래시 없이 예상치를 생략한다")
    func invalidDistance() {
        for distance in [-1, Double.nan, .infinity, .greatestFiniteMagnitude] {
            #expect(BookNavigationMetrics(remainingMeters: distance) == nil)
        }
    }
}
