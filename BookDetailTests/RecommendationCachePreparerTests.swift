import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RecommendationCachePreparerTests {
    @Test("저장된 표지는 재사용하고 새 표지만 받아 다음 인스턴스에서 복원한다")
    func downloadsOnlyMissingCovers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = RecommendationCacheFixture.book("a"), b = RecommendationCacheFixture.book("b")
        let store = RecommendationCacheStore(directory: directory)
        _ = try await store.save(books: [a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .distantPast)
        let calls = CoverCalls()
        let preparer = RecommendationCachePreparer(store: store, loadCover: { await calls.load($0) })
        let next = try await preparer.prepare([a, b])
        #expect(next.books == [a, b])
        #expect(await calls.urls == [b.imageURL!])
        let restored = try #require(try await RecommendationCacheStore(directory: directory).restore())
        #expect(restored.books == [a, b])
        #expect(restored.displayBooks.allSatisfy { $0.imageURL?.isFileURL == true })
    }

    @Test("새 표지 수신이 실패하면 마지막 정상 목록을 유지한다")
    func failedDownloadPreservesSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = RecommendationCacheFixture.book("a"), b = RecommendationCacheFixture.book("b")
        let store = RecommendationCacheStore(directory: directory)
        _ = try await store.save(books: [a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .distantPast)
        let preparer = RecommendationCachePreparer(store: store, loadCover: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: (any Error).self) { try await preparer.prepare([b]) }
        #expect(try await store.restore()?.books == [a])
    }

    @Test("이전 접속의 늦은 응답은 새 접속에서 준비한 저장본을 덮어쓰지 않는다")
    func ignoresSupersededPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = RecommendationCacheFixture.book("a"), b = RecommendationCacheFixture.book("b")
        let oldURL = a.imageURL!
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Data>.makeStream()
        let store = RecommendationCacheStore(directory: directory)
        let preparer = RecommendationCachePreparer(store: store, loadCover: { url in
            if url == oldURL {
                started.continuation.yield()
                for await data in gate.stream { return data }
                throw CancellationError()
            }
            return RecommendationCacheFixture.image
        })
        let old = Task { try await preparer.prepare([a]) }
        for await _ in started.stream { break }
        _ = try await preparer.prepare([b])
        gate.continuation.yield(RecommendationCacheFixture.image)
        gate.continuation.finish()
        switch await old.result {
        case .success: Issue.record("이전 준비 작업이 새 저장본을 덮어씀")
        case let .failure(error): #expect(error is CancellationError)
        }
        #expect(try await store.restore()?.books == [b])
    }

    @Test("표지 수신은 동시에 두 개까지만 실행한다")
    func boundsConcurrency() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let transport = ConcurrentCovers()
        let preparer = RecommendationCachePreparer(store: store, loadCover: { try await transport.load($0) })
        _ = try await preparer.prepare((0..<6).map { RecommendationCacheFixture.book(String($0)) })
        #expect(await transport.calls == 6)
        #expect(await transport.maximum == 2)
    }
}

private actor CoverCalls {
    var urls: [URL] = []
    func load(_ url: URL) -> Data {
        urls.append(url)
        return RecommendationCacheFixture.image
    }
}

private actor ConcurrentCovers {
    var calls = 0
    var maximum = 0
    private var active = 0
    func load(_ url: URL) async throws -> Data {
        calls += 1
        active += 1
        maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        return RecommendationCacheFixture.image
    }
}
