import Foundation

/// 소장 정보 응답을 일정 시간 재사용하고, 같은 책을 동시에 조회하면 요청 하나를 함께 기다린다.
/// 도서관 서버로 같은 요청이 반복되지 않게 하는 것이 목적이다.
actor BookHoldingsCache {
    private struct Entry {
        let holdings: [BookHolding]
        let expiresAt: Date
    }

    private struct Request {
        let token: Int
        let task: Task<[BookHolding], Error>
    }

    private var entries: [String: Entry] = [:]
    private var requests: [String: Request] = [:]
    private var nextToken = 0
    private let lifetime: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> Date

    init(
        lifetime: TimeInterval = 30 * 60,
        capacity: Int = 200,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(lifetime > 0 && capacity > 0)
        self.lifetime = lifetime
        self.capacity = capacity
        self.now = now
    }

    /// 만료되지 않은 값이 있으면 돌려주고, 같은 키의 요청이 진행 중이면 그 결과를 함께 기다린다.
    /// 실패와 빈 결과는 저장하지 않아 다음 조회에서 다시 요청한다.
    func holdings(
        for key: String,
        fetch: @escaping @Sendable () async throws -> [BookHolding]
    ) async throws -> [BookHolding] {
        if let entry = entries[key] {
            if entry.expiresAt > now() { return entry.holdings }
            entries[key] = nil
        }
        if let request = requests[key] {
            return try await request.task.value
        }

        nextToken += 1
        let token = nextToken
        let task = Task { try await fetch() }
        requests[key] = Request(token: token, task: task)
        do {
            let holdings = try await task.value
            finishRequest(key, token: token, holdings: holdings)
            return holdings
        } catch {
            finishRequest(key, token: token, holdings: nil)
            throw error
        }
    }

    private func finishRequest(_ key: String, token: Int, holdings: [BookHolding]?) {
        guard requests[key]?.token == token else { return }
        requests[key] = nil
        guard let holdings, !holdings.isEmpty else { return }
        insert(holdings, for: key)
    }

    private func insert(_ holdings: [BookHolding], for key: String) {
        let date = now()
        entries = entries.filter { $0.value.expiresAt > date }
        if entries[key] == nil, entries.count >= capacity,
           let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries[oldest] = nil
        }
        entries[key] = Entry(holdings: holdings, expiresAt: date.addingTimeInterval(lifetime))
    }
}
