import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

@Suite(.serialized)
struct BookHoldingsClientTests {
    private let recordID = "alma991000958759703286"

    @Test("Book의 원본 자료번호를 추출하고 유효하지 않은 식별자는 조회하지 않는다")
    @MainActor
    func extractsRecordID() {
        func book(_ id: String, control: String? = nil) -> Book {
            Book(id: id, isbn: "9791139723281", controlNumber: control, title: "책", author: "저자",
                 publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        }
        #expect(BookHoldingsClient.recordID(for: book("primo:\(recordID)")) == recordID)
        #expect(BookHoldingsClient.recordID(for: book("local", control: recordID)) == recordID)
        #expect(BookHoldingsClient.recordID(for: book("local", control: "alma123")) == nil)
        #expect(BookHoldingsClient.recordID(for: book("9791139723281")) == nil)
    }

    @Test("자료번호로 요청하고 청구기호·상태가 다른 소장처 전체를 반환한다")
    func preservesAllHoldings() async throws {
        let recordID = recordID
        let session = makeSession { request in
            #expect(request.url?.host == "pobook-api-dev.fpmaps.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-relay-token-not-a-provider-key")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first { $0.name == "q" }?.value == "any,contains,991000958759703286")
            #expect(query.first { $0.name == "skipDelivery" }?.value == "false")
            return response(request, """
            {"docs":[{"pnx":{"control":{"recordid":["\(recordID)"]}},"delivery":{"holding":[
              {"holdId":"a","callNumber":"UNAVAILABLE","availabilityStatus":"unavailable"},
              {"holdId":"b","callNumber":" QA76.9 .A43 ","subLocation":"단행본3층","subLocationCode":"c3b","availabilityStatus":"available"}
            ]}}]}
            """)
        }
        defer { session.invalidateAndCancel() }
        let result = try await PrimoBookHoldingsService(relay: .test { try await session.data(for: $0) }).fetch(recordID: recordID)
        #expect(result.map(\.callNumber) == ["UNAVAILABLE", "QA76.9 .A43"])
        #expect(result.map(\.availability) == ["unavailable", "available"])
        #expect(result[1].locationCode == "c3b")
    }

    @Test("알 수 없는 대출 상태의 원본 값을 보존한다", arguments: ["check_holdings", "unexpected"])
    func preservesUnknownAvailability(_ status: String) async throws {
        let recordID = recordID
        let session = makeSession { request in
            response(request, """
            {"docs":[{"pnx":{"control":{"recordid":["\(recordID)"]}},"delivery":{"holding":[{"callNumber":"Q1","availabilityStatus":"\(status)"}]}}]}
            """)
        }
        defer { session.invalidateAndCancel() }
        let result = try await PrimoBookHoldingsService(relay: .test { try await session.data(for: $0) }).fetch(recordID: recordID)
        #expect(result.first?.availability == status)
        #expect(result.first?.availabilityText == "대출 상태 확인 필요")
    }

    @Test("대상 자료번호와 다른 레코드의 소장처로 대체하지 않는다")
    func rejectsUnrelatedRecord() async throws {
        let session = makeSession { request in
            response(request, #"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703280"]}},"delivery":{"holding":[{"callNumber":"WRONG"}]}}]}"#)
        }
        defer { session.invalidateAndCancel() }
        #expect(try await PrimoBookHoldingsService(relay: .test { try await session.data(for: $0) }).fetch(recordID: recordID) == [])
    }

    @Test("유효하지 않은 자료번호는 네트워크 호출 전에 거절한다")
    func rejectsInvalidIDBeforeLoading() async {
        let session = makeSession { request in
            Issue.record("유효하지 않은 식별자로 요청하면 안 된다")
            return response(request, #"{"docs":[]}"#)
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: BookHoldingsError.self) {
            try await PrimoBookHoldingsService(relay: .test { try await session.data(for: $0) }).fetch(recordID: "alma123")
        }
    }

    @Test("HTTP 오류와 잘못된 응답을 소장 없음으로 숨기지 않는다", arguments: [400, 200])
    func invalidResponse(_ status: Int) async {
        let session = makeSession { request in response(request, #"{"error":"failed"}"#, status: status) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await PrimoBookHoldingsService(relay: .test { try await session.data(for: $0) }).fetch(recordID: recordID)
        }
    }

    @Test("짧은 요청 제한은 재시도하고 긴 예산 제한은 즉시 중단한다", arguments: ["1", "60"])
    func respectsRelayRetryAfter(_ retryAfter: String) async throws {
        let calls = Mutex(0)
        let relay = BookAPIClient.test { request in
            let attempt = calls.withLock { $0 += 1; return $0 }
            return (Data(#"{"docs":[]}"#.utf8), HTTPURLResponse(
                url: request.url!, statusCode: attempt == 1 ? 429 : 200, httpVersion: nil,
                headerFields: ["Retry-After": retryAfter]
            )!)
        }
        let service = PrimoBookHoldingsService(relay: relay)
        if retryAfter == "1" {
            #expect(try await service.fetch(recordID: recordID) == [])
            #expect(calls.withLock { $0 } == 2)
        } else {
            await #expect(throws: BookHoldingsError.serviceUnavailable) {
                try await service.fetch(recordID: recordID)
            }
            #expect(calls.withLock { $0 } == 1)
        }
    }

    @Test("일시적 전송 오류는 같은 요청을 최대 3회 안에서 자동 복구한다", arguments: [
        URLError.timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed
    ])
    func retriesTransientTransportErrors(_ code: URLError.Code) async throws {
        let calls = Mutex(0)
        let delays = Mutex<[Duration]>([])
        let relay = BookAPIClient.test { request in
            let attempt = calls.withLock { $0 += 1; return $0 }
            if attempt < 3 { throw URLError(code) }
            return response(request, #"{"docs":[]}"#)
        }
        let service = PrimoBookHoldingsService(relay: relay, sleep: { delay in
            delays.withLock { $0.append(delay) }
        })
        #expect(try await service.fetch(recordID: recordID) == [])
        #expect(calls.withLock { $0 } == 3)
        #expect(delays.withLock { $0 } == [.milliseconds(500), .seconds(1)])
    }

    @Test("전송 오류와 HTTP 오류가 섞여도 총 요청은 3회를 넘지 않는다")
    func sharesRetryBudgetAcrossErrorKinds() async throws {
        let calls = Mutex(0)
        let relay = BookAPIClient.test { request in
            let attempt = calls.withLock { $0 += 1; return $0 }
            if attempt == 1 { throw URLError(.timedOut) }
            return response(request, #"{"docs":[]}"#, status: 503)
        }
        let service = PrimoBookHoldingsService(relay: relay, sleep: { _ in })
        await #expect(throws: BookHoldingsError.self) { try await service.fetch(recordID: recordID) }
        #expect(calls.withLock { $0 } == 3)
    }

    @Test("전송 오류가 계속되면 3회 후 중단한다")
    func stopsAfterTransportRetryBudget() async {
        let calls = Mutex(0)
        let service = PrimoBookHoldingsService(relay: .test { _ in
            calls.withLock { $0 += 1 }
            throw URLError(.notConnectedToInternet)
        }, sleep: { _ in })
        await #expect(throws: URLError.self) { try await service.fetch(recordID: recordID) }
        #expect(calls.withLock { $0 } == 3)
    }

    @Test("인증·입력·응답 오류는 자동 재시도하지 않는다", arguments: [400, 401, 403, 200])
    func doesNotRetryPermanentHTTPFailures(_ status: Int) async {
        let calls = Mutex(0)
        let service = PrimoBookHoldingsService(relay: .test { request in
            calls.withLock { $0 += 1 }
            return response(request, #"{"error":"invalid"}"#, status: status)
        }, sleep: { _ in Issue.record("영구 오류에는 재시도 대기가 없어야 합니다") })
        await #expect(throws: BookHoldingsError.self) { try await service.fetch(recordID: recordID) }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("취소와 영구 전송 오류는 자동 재시도하지 않는다", arguments: [
        URLError.cancelled, .badURL, .unsupportedURL, .serverCertificateUntrusted
    ])
    func doesNotRetryPermanentTransportFailures(_ code: URLError.Code) async {
        let calls = Mutex(0)
        let service = PrimoBookHoldingsService(relay: .test { _ in
            calls.withLock { $0 += 1 }
            throw URLError(code)
        }, sleep: { _ in Issue.record("이 오류에는 재시도 대기가 없어야 합니다") })
        await #expect(throws: URLError.self) { try await service.fetch(recordID: recordID) }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("재시도 대기 중 취소하면 추가 요청을 보내지 않는다")
    func cancelsDuringRetryDelay() async {
        let calls = Mutex(0)
        let sleeping = AsyncStream<Void>.makeStream()
        defer { sleeping.continuation.finish() }
        let service = PrimoBookHoldingsService(relay: .test { _ in
            calls.withLock { $0 += 1 }
            throw URLError(.timedOut)
        }, sleep: { _ in
            sleeping.continuation.yield()
            try await Task.sleep(for: .seconds(60))
        })
        let recordID = recordID
        let task = Task { try await service.fetch(recordID: recordID) }
        var iterator = sleeping.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("취소한 요청이 성공하면 안 됩니다")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(calls.withLock { $0 } == 1)
    }

    private func makeSession(
        _ handler: @escaping @Sendable (URLRequest) -> (Data, URLResponse)
    ) -> URLSession {
        HoldingsURLProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HoldingsURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private nonisolated func response(_ request: URLRequest, _ json: String, status: Int = 200) -> (Data, URLResponse) {
    (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private final class HoldingsURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) -> (Data, URLResponse))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
