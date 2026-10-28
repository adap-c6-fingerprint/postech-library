import Foundation

/// 실제 경로 계산 결과를 연결할 때 교체할 상세 화면의 표시 데이터.
nonisolated struct BookRouteSummary: Equatable, Sendable {
    var walkingMinutes: Int
    var stepCount: Int
    var distanceMeters: Int
    var isMock: Bool

    static let mock = Self(walkingMinutes: 3, stepCount: 5, distanceMeters: 120, isMock: true)
}
