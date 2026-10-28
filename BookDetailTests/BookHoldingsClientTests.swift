import Foundation
import Testing
@testable import fingerprint_library

struct BookHoldingsClientTests {
    private func book(id: String = "primo:alma123", isbn: String? = "9791139723281") -> Book {
        Book(id: id, isbn: isbn, controlNumber: id, title: "책", author: "저자",
             publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }

    private func response(_ request: URLRequest, _ json: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    @Test("공개 Primo를 인증 없이 조회하고 같은 소장의 청구기호·대출 상태를 표시한다")
    func selectsAvailableHolding() async throws {
        let service = PrimoBookHoldingsService(load: { request in
            #expect(request.url?.host == "postech.primo.exlibrisgroup.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first { $0.name == "q" }?.value == "any,contains,123")
            #expect(query.first { $0.name == "skipDelivery" }?.value == "false")
            return response(request, """
            {"docs":[{"pnx":{"control":{"recordid":["alma123"]}},"delivery":{
            "deliveryCategory":["Alma-P"],"holding":[
              {"callNumber":"UNAVAILABLE","availabilityStatus":"unavailable"},
              {"callNumber":" QA76.9 .A43 ","subLocation":"단행본3층","subLocationCode":"c3b","availabilityStatus":"available"}
            ]}}]}
            """)
        })
        let result = try await service.fetch(for: book())
        #expect(result?.callNumber == "QA76.9 .A43")
        #expect(result?.locationCode == "c3b")
        #expect(result?.availability == .available)
    }

    @Test("소장 없음 레코드는 같은 ISBN의 실물 소장 레코드를 다시 조회한다")
    func fallsBackToMatchingISBN() async throws {
        let service = PrimoBookHoldingsService(load: { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .first { $0.name == "q" }!.value!
            if query.hasPrefix("any,") {
                return response(request, """
                {"docs":[{"pnx":{"control":{"recordid":["alma123"]}},"delivery":{"availability":["no_inventory"]}}]}
                """)
            }
            #expect(query == "isbn,exact,9791139723281")
            return response(request, """
            {"docs":[
              {"pnx":{"control":{"recordid":["alma999"]},"addata":{"isbn":["9788966260959"]}},"delivery":{"holding":[{"callNumber":"WRONG","availabilityStatus":"available"}]}},
              {"pnx":{"control":{"recordid":["alma456"]},"addata":{"isbn":["9791139723281"]}},"delivery":{"bestlocation":{"callNumber":"BF637.S8 .N47 2025","availabilityStatus":"unavailable"}}}
            ]}
            """)
        })
        let result = try await service.fetch(for: book())
        #expect(result?.recordID == "alma456")
        #expect(result?.callNumber == "BF637.S8 .N47 2025")
        #expect(result?.availability == .unavailable)
    }

    @Test("알 수 없는 상태를 대출 불가능으로 바꾸지 않는다", arguments: ["check_holdings", "", "unexpected"])
    func unknownAvailability(_ status: String) async throws {
        let service = PrimoBookHoldingsService(load: { request in
            response(request, """
            {"docs":[{"pnx":{"control":{"recordid":["alma123"]}},"delivery":{"holding":[{"callNumber":"Q1","availabilityStatus":"\(status)"}]}}]}
            """)
        })
        let result = try await service.fetch(for: book())
        #expect(result?.availability == .unknown)
    }

    @Test("엉뚱한 레코드와 전자자료의 소장을 선택하지 않는다")
    func ignoresUnrelatedAndElectronicRecords() async throws {
        let service = PrimoBookHoldingsService(load: { request in
            response(request, """
            {"docs":[
              {"pnx":{"control":{"recordid":["alma999"]}},"delivery":{"holding":[{"callNumber":"WRONG","availabilityStatus":"available"}]}},
              {"pnx":{"control":{"recordid":["alma123"]}},"delivery":{"deliveryCategory":["Alma-E"],"holding":[{"callNumber":"ONLINE","availabilityStatus":"available"}]}}
            ]}
            """)
        })
        let result = try await service.fetch(for: book(isbn: nil))
        #expect(result == nil)
    }

    @Test("소장·ISBN이 없으면 대출 불가능으로 추정하지 않는다")
    func missingInventory() async throws {
        let service = PrimoBookHoldingsService(load: { request in response(request, "{\"docs\":[]}") })
        #expect(try await service.fetch(for: book(isbn: nil)) == nil)
    }

    @Test("서버 오류와 잘못된 응답은 빈 소장으로 처리하지 않는다", arguments: [500, 200])
    func invalidResponse(_ status: Int) async {
        let service = PrimoBookHoldingsService(load: { request in response(request, "{\"error\":\"failed\"}", status: status) })
        await #expect(throws: (any Error).self) {
            try await service.fetch(for: book())
        }
    }
}
