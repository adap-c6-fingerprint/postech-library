import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

struct BookHoldingsCacheTests {
    private let holdings = [
        BookHolding(
            holdingID: "1", institutionCode: nil, libraryCode: "MAIN", locationCode: "A",
            locationName: "자료실", callNumber: "005.1", availability: "available"
        )
    ]

    @Test func 삼십분_안에는_같은_책을_다시_요청하지_않는다() async throws {
        let clock = TestClock()
        let calls = Mutex(0)
        let cache = BookHoldingsCache(now: { clock.now })
        let fetch: @Sendable () async throws -> [BookHolding] = { [holdings] in
            calls.withLock { $0 += 1 }
            return holdings
        }

        #expect(try await cache.holdings(for: "a", fetch: fetch) == holdings)
        clock.advance(by: 30 * 60 - 1)
        #expect(try await cache.holdings(for: "a", fetch: fetch) == holdings)
        #expect(calls.withLock { $0 } == 1)

        clock.advance(by: 1)
        _ = try await cache.holdings(for: "a", fetch: fetch)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func 빈_결과는_저장하지_않고_다시_요청한다() async throws {
        let calls = Mutex(0)
        let cache = BookHoldingsCache()
        let fetch: @Sendable () async throws -> [BookHolding] = {
            calls.withLock { $0 += 1 }
            return []
        }

        _ = try await cache.holdings(for: "a", fetch: fetch)
        _ = try await cache.holdings(for: "a", fetch: fetch)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func 실패는_저장하지_않고_다시_요청한다() async throws {
        struct Failure: Error {}
        let calls = Mutex(0)
        let cache = BookHoldingsCache()
        let failing: @Sendable () async throws -> [BookHolding] = {
            calls.withLock { $0 += 1 }
            throw Failure()
        }

        await #expect(throws: Failure.self) { try await cache.holdings(for: "a", fetch: failing) }
        let result = try await cache.holdings(for: "a") { [holdings] in
            calls.withLock { $0 += 1 }
            return holdings
        }
        #expect(result == holdings)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func 동시에_같은_책을_조회하면_요청을_한_번만_보낸다() async throws {
        let calls = Mutex(0)
        let isOpen = Mutex(false)
        let cache = BookHoldingsCache()
        let fetch: @Sendable () async throws -> [BookHolding] = { [holdings] in
            calls.withLock { $0 += 1 }
            while !isOpen.withLock({ $0 }) { await Task.yield() }
            return holdings
        }

        let first = Task { try await cache.holdings(for: "a", fetch: fetch) }
        while calls.withLock({ $0 }) == 0 { await Task.yield() }
        let second = Task { try await cache.holdings(for: "a", fetch: fetch) }
        for _ in 0..<100 { await Task.yield() }
        isOpen.withLock { $0 = true }

        #expect(try await first.value == holdings)
        #expect(try await second.value == holdings)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func 다른_책은_각각_요청한다() async throws {
        let calls = Mutex(0)
        let cache = BookHoldingsCache()
        let fetch: @Sendable () async throws -> [BookHolding] = { [holdings] in
            calls.withLock { $0 += 1 }
            return holdings
        }

        _ = try await cache.holdings(for: "a", fetch: fetch)
        _ = try await cache.holdings(for: "b", fetch: fetch)
        #expect(calls.withLock { $0 } == 2)
    }
}

private final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSinceReferenceDate: 0))

    var now: Date { date.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
