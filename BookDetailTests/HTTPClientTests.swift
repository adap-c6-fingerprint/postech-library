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

    @Test("Task가 취소되지 않았으면 원래 전송 오류를 유지한다", arguments: [URLError.Code.timedOut, .cancelled])
    func preservesTransportError(code: URLError.Code) async {
        let client = HTTPClient(load: { _ in throw URLError(code) })
        do {
            _ = try await client.send(URLRequest(url: url))
            Issue.record("원래 전송 오류가 전달되어야 한다")
        } catch let error as URLError {
            #expect(error.code == code)
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

    @Test("전송기가 취소된 Task에서 URL 취소 오류를 던져도 CancellationError로 전달한다")
    func normalizesTransportFailureAfterCancellation() async {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let client = HTTPClient(load: { _ in
            started.continuation.yield()
            for await _ in gate.stream { break }
            throw URLError(.cancelled)
        })
        let task = Task { try await client.send(URLRequest(url: url)) }
        for await _ in started.stream { break }
        task.cancel()
        gate.continuation.finish()
        started.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("실제 URLSession의 진행 중 요청을 취소하면 CancellationError로 전달한다")
    func normalizesURLSessionCancellation() async {
        let requestURL = URL(string: "https://example.test/\(UUID().uuidString)")!
        let started = AsyncStream<Void>.makeStream()
        CancellationURLProtocol.started.withLock { $0[requestURL] = started.continuation }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            CancellationURLProtocol.started.withLock { $0[requestURL] = nil }
            started.continuation.finish()
        }
        let client = HTTPClient.urlSession(session)
        let task = Task {
            defer { started.continuation.finish() }
            return try await client.send(URLRequest(url: requestURL))
        }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// 외부 서버 없이 URLSession의 요청 시작·취소 경로를 검증한다.
private nonisolated final class CancellationURLProtocol: URLProtocol, @unchecked Sendable {
    static let started = Mutex<[URL: AsyncStream<Void>.Continuation]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let continuation = Self.started.withLock { $0[url] }
        continuation?.yield()
    }

    override func stopLoading() {}
}
