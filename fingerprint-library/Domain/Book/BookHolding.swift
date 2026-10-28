import Foundation

/// 도서의 소장처. 서지 ID·소장 ID·지도 fixture ID는 각각 다른 식별자다.
nonisolated struct BookHolding: Equatable, Identifiable, Sendable {
    let holdingID: String?
    let institutionCode: String?
    let libraryCode: String?
    let locationCode: String?
    let locationName: String?
    let callNumber: String?
    let availability: String?

    var id: String {
        [institutionCode, libraryCode, locationCode, locationName, callNumber, holdingID]
            .map { $0 ?? "" }.joined(separator: "\u{1F}")
    }

    var availabilityText: String {
        switch availability {
        case "available": "대출 가능"
        case "unavailable": "대출 중 또는 이용 불가"
        default: "대출 상태 확인 필요"
        }
    }
}
