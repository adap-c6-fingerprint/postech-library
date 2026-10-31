import Foundation
import Testing
@testable import fingerprint_library

struct Yes24BookCoverTests {
    @Test("요청 ISBN과 정확히 일치하는 책의 HTTPS 표지만 선택한다")
    func selectsExactEdition() async throws {
        let body = #"{"success":true,"data":{"items":[{"isbn13":"9780131103627","cover":"https://image.yes24.com/goods/wrong/L"},{"isbn13":"9788937460777","cover":"https://image.yes24.com/goods/372300/L"}]}}"#
        let service = Yes24BookDetailService(relay: .test { request in
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-relay-token-not-a-provider-key")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
                URLQueryItem(name: "searchType", value: "ISBN13"), URLQueryItem(name: "query", value: "9788937460777")
            ])
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await service.fetchCoverURL(isbn13: "9788937460777")
                == URL(string: "https://image.yes24.com/goods/372300/L"))
    }

    @Test("다른 판본·표지 누락·비정상 주소를 표지 없음으로 처리한다", arguments: [
        #"{"isbn13":"9780131103627","cover":"https://image.yes24.com/goods/1/L"}"#,
        #"{"isbn13":"9788937460777","cover":null}"#,
        #"{"isbn13":"9788937460777","cover":" "}"#,
        #"{"isbn13":"9788937460777","cover":"http://image.yes24.com/goods/1/L"}"#,
        #"{"isbn13":"9788937460777","cover":"https://yes24.com.example.org/1"}"#
    ])
    func rejectsMissingOrUnsafeCover(item: String) async throws {
        let body = "{\"success\":true,\"data\":{\"items\":[\(item)]}}"
        let service = Yes24BookDetailService(relay: .test { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await service.fetchCoverURL(isbn13: "9788937460777") == nil)
    }

    @Test("같은 ISBN의 동시 조회·성공·미등록 결과를 공유하고 실패는 재시도한다")
    func sharesRequestsAndRetriesErrors() async throws {
        let calls = Calls()
        let gate = AsyncStream<Void>.makeStream()
        let resolver = Yes24BookCoverResolver { isbn in
            await calls.record(isbn)
            for await _ in gate.stream { break }
            return URL(string: "https://image.yes24.com/goods/372300/L")
        }
        let first = Task { try await resolver.coverURL(for: "8937460777") }
        let second = Task { try await resolver.coverURL(for: "9788937460777") }
        while await calls.values.isEmpty { await Task.yield() }
        gate.continuation.yield()
        gate.continuation.finish()
        #expect(try await first.value == second.value)
        _ = try await resolver.coverURL(for: "9788937460777")
        #expect(await calls.values == ["9788937460777"])

        let attempts = Calls()
        let retrying = Yes24BookCoverResolver { isbn in
            let count = await attempts.record(isbn)
            if count == 1 { throw URLError(.timedOut) }
            return nil
        }
        await #expect(throws: URLError.self) { try await retrying.coverURL(for: "9788937460777") }
        #expect(try await retrying.coverURL(for: "9788937460777") == nil)
        #expect(try await retrying.coverURL(for: "9788937460777") == nil)
        #expect(try await retrying.coverURL(for: "invalid") == nil)
        #expect(await attempts.values.count == 2)
    }

    @Test("캐시 유효기간이 지나면 미등록 책도 다시 확인한다")
    func refreshesExpiredResults() async throws {
        let calls = Calls()
        let resolver = Yes24BookCoverResolver(lifetime: 0) { isbn in
            await calls.record(isbn)
            return nil
        }
        _ = try await resolver.coverURL(for: "9788937460777")
        _ = try await resolver.coverURL(for: "9788937460777")
        #expect(await calls.values.count == 2)
    }

    private actor Calls {
        var values: [String] = []
        @discardableResult
        func record(_ value: String) -> Int { values.append(value); return values.count }
    }
}
