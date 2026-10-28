import Foundation

/// Primo의 한 소장 위치. 청구기호와 대출 상태는 같은 소장 항목에서 가져온다.
nonisolated struct BookHolding: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable
        case unknown
    }

    let recordID: String
    let callNumber: String?
    let location: String?
    let locationCode: String?
    let availability: Availability
}

/// 실제 경로 계산 결과를 연결할 때 교체할 상세 화면의 표시 데이터.
nonisolated struct BookRouteSummary: Equatable, Sendable {
    var walkingMinutes: Int
    var stepCount: Int
    var distanceMeters: Int
    var isMock: Bool

    static let mock = Self(walkingMinutes: 3, stepCount: 5, distanceMeters: 120, isMock: true)
}
