import Foundation
import Testing
@testable import fingerprint_library

struct PrimoHoldingsMapperTests {
    private let recordID = "alma991000958759703286"

    @Test("식별 정보가 누락되거나 null인 문서가 섞여도 정상 대상 문서의 위치를 읽는다", arguments: [
        #"{}"#, #"{"pnx":null}"#, #"{"pnx":{}}"#, #"{"pnx":{"control":null}}"#,
        #"{"pnx":{"control":{}}}"#, #"{"pnx":{"control":{"recordid":null}}}"#,
        #"{"pnx":{"control":{"recordid":[]}}}"#
    ])
    func skipsDocumentsWithoutIdentity(incomplete: String) throws {
        let target = #"{"pnx":{"control":{"recordid":["alma991000958759703286"]}},"delivery":{"holding":[{"holdId":"target","callNumber":"RC263 .R632 1990"}]}}"#
        let mixed = Data("{\"docs\":[\(incomplete),\(target)]}".utf8)
        let holdings = try PrimoHoldingsMapper.decode(mixed, recordID: recordID)
        #expect(holdings.count == 1)
        #expect(holdings.first?.holdingID == "target")
        #expect(holdings.first?.callNumber == "RC263 .R632 1990")

        let unidentified = Data("{\"docs\":[\(incomplete)]}".utf8)
        #expect(try PrimoHoldingsMapper.decode(unidentified, recordID: recordID).isEmpty)
    }

    @Test("실제 top-level holding·holdId·위치 코드와 복수 소장처를 보존한다")
    func topLevelHoldings() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]}},"delivery":{"holding":[{"organization":"82POSTECH_INST","libraryCode":"MAIN","subLocation":"단행본3층","subLocationCode":"c3b","callNumber":"CB113.H4 .H3713 2015","holdId":"holding-a","availabilityStatus":"available"},{"organization":"82POSTECH_INST","libraryCode":"MAIN","subLocation":"스마트도서관","subLocationCode":"smart","callNumber":"CB113.H4 .H3713 2015","holdId":"holding-b","availabilityStatus":"unavailable"}]}}]}"#.utf8)
        let result = try PrimoHoldingsMapper.decode(data, recordID: recordID)
        #expect(result.count == 2)
        #expect(result.map(\.holdingID) == ["holding-a", "holding-b"])
        #expect(result.map(\.locationCode) == ["c3b", "smart"])
        #expect(result[1].availability == "unavailable")
    }

    @Test("문서의 pnx.delivery·holdingId 변형도 처리한다")
    func nestedDelivery() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"delivery":{"holding":[{"libraryCode":"MAIN","subLocation":"3F_WEST","subLocationCodeName":"3층 서편 일반서고","callNumber":" RC263 .R632 1990 ","holdingId":" h-1 "}]}}}]}"#.utf8)
        let holding = try #require(PrimoHoldingsMapper.decode(data, recordID: recordID).first)
        #expect(holding.holdingID == "h-1")
        #expect(holding.locationName == "3층 서편 일반서고")
        #expect(holding.locationCode == "3F_WEST")
        #expect(holding.callNumber == "RC263 .R632 1990")
    }

    @Test("대체 PNX는 공식 서브필드를 사용하고 온라인 자료는 제외한다")
    func availabilityFallback() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"display":{"availlibrary":["$$I82POSTECH_INST$$LMAIN$$1단행본3층$$2RC263 .R632 1990$$Savailable$$Zc3b$$J123","$$I82POSTECH_INST$$LMAIN$$1단행본3층$$2RC263 .R632 1990$$Savailable$$Zc3b$$J123","$$I82POSTECH_INST$$LMAIN$$1전자책$$2RC263$$Savailable$$9ONLINE"]}}}]}"#.utf8)
        let holdings = try PrimoHoldingsMapper.decode(data, recordID: recordID)
        #expect(holdings.count == 1)
        #expect(holdings.first?.institutionCode == "82POSTECH_INST")
        #expect(holdings.first?.libraryCode == "MAIN")
        #expect(holdings.first?.locationCode == "c3b")
        #expect(holdings.first?.availability == "available")
    }

    @Test("빈 holding 응답에 bestlocation·PNX의 과거 위치를 섞지 않는다")
    func explicitEmptyHoldings() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"display":{"availlibrary":["$$I82POSTECH_INST$$LMAIN$$1단행본3층$$2RC263$$Zc3b"]}},"delivery":{"holding":[],"bestlocation":{"callNumber":"RC263"}}}]}"#.utf8)
        #expect(try PrimoHoldingsMapper.decode(data, recordID: recordID).isEmpty)
    }

    @Test("다른 판본·부분 일치 도서의 위치로 대체하지 않는다")
    func rejectsDifferentRecord() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma9910009587597032861"]}},"delivery":{"holding":[{"callNumber":"RC263"}]}}]}"#.utf8)
        #expect(try PrimoHoldingsMapper.decode(data, recordID: recordID).isEmpty)
    }

    @Test("API 오류 객체는 소장 정보 없음으로 숨기지 않는다")
    func rejectsMalformedResponse() {
        #expect(throws: (any Error).self) {
            try PrimoHoldingsMapper.decode(Data(#"{"error":"unavailable"}"#.utf8), recordID: recordID)
        }
    }
}
