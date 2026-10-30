import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

nonisolated struct HTTPClientTests {
    private let url = URL(string: "https://example.test/books")!

    @Test("본문·헤더·상태 코드를 보존하고 공통 전송은 임의로 재시도하지 않는다", arguments: [200, 404, 429, 503])
    func preservesHTTPResponse(status: Int) async throws {
        let calls = Mutex(0)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("body".utf8)
        request.setValue("test-key", forHTTPHeaderField: "X-Api-Key")
        let client = HTTPClient(load: { request in
            calls.withLock { $0 += 1 }
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody == Data("body".utf8))
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "test-key")
            return (Data("response".utf8), HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Retry-After": "2"]
            )!)
        })
        let result = try await client.send(request)
        #expect(result.data == Data("response".utf8))
        #expect(result.response.statusCode == status)
        #expect(result.response.value(forHTTPHeaderField: "Retry-After") == "2")
        #expect(result.isSuccessful == (status == 200))
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("HTTP 응답이 아니면 공통 경계에서 거절한다")
    func rejectsNonHTTPResponse() async {
        let client = HTTPClient(load: { request in
            (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        })
        await #expect(throws: HTTPClientError.self) { try await client.send(URLRequest(url: url)) }
    }

    @Test("전송 오류를 HTTP 상태 오류로 바꾸지 않는다")
    func preservesTransportError() async {
        let client = HTTPClient(load: { _ in throw URLError(.timedOut) })
        do {
            _ = try await client.send(URLRequest(url: url))
            Issue.record("시간 초과 오류가 전달되어야 한다")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("전송 오류가 변경됨: \(error)")
        }
    }

    @Test("이미 취소된 작업은 전송을 시작하지 않는다")
    func rejectsCancelledRequestBeforeLoading() async {
        let calls = Mutex(0)
        let gate = AsyncStream<Void>.makeStream()
        let client = HTTPClient(load: { request in
            calls.withLock { $0 += 1 }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let task = Task {
            for await _ in gate.stream { break }
            return try await client.send(URLRequest(url: url))
        }
        task.cancel()
        gate.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("전송기가 취소 후 응답을 반환해도 성공 결과로 내보내지 않는다")
    func rejectsResponseAfterCancellation() async {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let client = HTTPClient(load: { request in
            started.continuation.yield()
            for await _ in gate.stream { break }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let task = Task { try await client.send(URLRequest(url: url)) }
        for await _ in started.stream { break }
        task.cancel()
        gate.continuation.finish()
        started.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
