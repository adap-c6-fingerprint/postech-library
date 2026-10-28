import Foundation
import Testing
@testable import fingerprint_library

struct BookCardLibraryInfoTests {
    @Test("위치와 이용 가능 상태를 같은 소장처에서 선택한다")
    func selectsAvailableHolding() {
        let info = BookCardLibraryInfo(holdings: [
            holding("3층", call: "QA1", status: "unavailable"),
            holding("4층", call: "QA2", status: "available")
        ])
        #expect(info.location == "4층 QA2")
        #expect(info.availability == .available)
        #expect(info.additionalLocationCount == 1)
    }

    @Test("다른 도서관의 상태를 본관 위치에 붙이지 않는다")
    func prefersMainLibraryWithoutMixingStatus() {
        let other = holding("다른 도서관", call: "OTHER", status: "available", library: "OTHER")
        let main = holding("3층", call: "MAIN", status: "unavailable")
        let info = BookCardLibraryInfo(holdings: [other, main])
        #expect(info.location == "3층 MAIN")
        #expect(info.availability == .unavailable)
        #expect(BookCardLibraryInfo(holdings: [other]).location == "다른 도서관 OTHER")
    }

    @Test("빈 소장 정보와 알 수 없는 이용 상태를 대출 가능으로 추정하지 않는다")
    func handlesMissingInformation() {
        let empty = BookCardLibraryInfo(holdings: [])
        #expect(empty.location == nil)
        #expect(empty.availability == .unknown)
        #expect(empty.additionalLocationCount == 0)
        let unknown = BookCardLibraryInfo(holdings: [holding(" ", call: " ", status: "unknown")])
        #expect(unknown.location == nil)
        #expect(unknown.availability == .unknown)
    }

    @Test("같은 소장 위치에 있는 여러 부를 별도 위치로 세지 않는다")
    func countsLocationsRatherThanCopies() {
        let info = BookCardLibraryInfo(holdings: [
            holding("3층", call: "QA1", status: "available"),
            holding("3층", call: "QA2", status: "unavailable"),
            holding("4층", call: "QA1", status: "available")
        ])
        #expect(info.additionalLocationCount == 1)
    }

    private func holding(_ location: String, call: String?, status: String?, library: String = "MAIN") -> BookHolding {
        .init(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: library,
              locationCode: location, locationName: location, callNumber: call, availability: status)
    }
}
