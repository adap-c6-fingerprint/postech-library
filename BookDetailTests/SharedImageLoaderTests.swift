import Foundation
import Testing
@testable import fingerprint_library

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SharedImageLoaderTests {
    private let url = URL(string: "https://example.invalid/cover")!

    @Test("저장된 로컬 표지는 첫 표시 상태를 만들 때 네트워크 없이 즉시 재사용한다")
    func synchronouslyRestoresLocalCover() async throws {
        var reads = 0
        let local = URL(fileURLWithPath: "/offline/cover.png")
        let loader = SharedImageLoader<String>(
            readLocalImage: { url in
                guard url.isFileURL else { return nil }
                reads += 1
                return "disk cover"
            }, cost: { _ in 1 }
        ) { _ in
            Issue.record("완료된 로컬 표지는 네트워크 작업을 시작하지 않아야 한다")
            return "network"
        }
        #expect(loader.cachedImage(for: local) == "disk cover")
        #expect(try await loader.image(for: local) == "disk cover")
        #expect(reads == 1)
    }

    @Test("완료한 표지는 다음 요청에서 네트워크 작업 없이 재사용한다")
    func reusesCompletedImage() async throws {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            return "cover"
        }
        #expect(try await loader.image(for: url) == "cover")
        #expect(loader.cachedImage(for: url) == "cover")
        #expect(try await loader.image(for: url) == "cover")
        #expect(calls == 1)
    }

    @Test("같은 URL은 작업을 공유하며 한 화면의 취소가 다른 화면을 취소하지 않는다")
    func sharesRequestWithIndependentCancellation() async throws {
        let transport = ImageTransport()
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            try await transport.load()
        }
        let first = Task { try await loader.image(for: url) }
        await transport.waitUntilStarted()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await loader.image(for: url)
        }
        while !secondStarted { await Task.yield() }
        first.cancel()
        do {
            _ = try await first.value
            Issue.record("취소한 화면의 요청이 성공함")
        } catch is CancellationError {
        }
        await transport.succeed("shared cover")
        #expect(try await second.value == "shared cover")
        #expect(await transport.callCount == 1)
        #expect(loader.cachedImage(for: url) == "shared cover")
    }

    @Test("마지막 화면이 떠나면 유예 후 작업을 취소하고 다음 방문은 새 작업을 시작한다")
    func cancelsUnobservedRequest() async throws {
        let transport = ImageTransport()
        let loader = SharedImageLoader<String>(
            cancellationDelay: .zero, cost: { _ in 1 }
        ) { _ in try await transport.load() }
        let first = Task { try await loader.image(for: url) }
        await transport.waitUntilStarted()
        first.cancel()
        _ = await first.result
        await transport.waitUntilCancelled()

        let second = Task { try await loader.image(for: url) }
        await transport.waitUntilStarted(count: 2)
        await transport.succeed("new cover")
        #expect(try await second.value == "new cover")
        #expect(await transport.callCount == 2)
    }

    @Test("실패는 캐시하지 않고 다음 방문에서 재시도한다")
    func retriesFailure() async throws {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return "recovered"
        }
        do {
            _ = try await loader.image(for: url)
            Issue.record("실패해야 하는 요청이 성공함")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
        #expect(loader.cachedImage(for: url) == nil)
        #expect(try await loader.image(for: url) == "recovered")
        #expect(calls == 2)
    }

    @Test("마지막 화면 취소 직후 돌아오면 유예 중인 작업을 다시 공유한다")
    func rejoinsDuringGracePeriod() async throws {
        let transport = ImageTransport()
        let loader = SharedImageLoader<String>(
            cancellationDelay: .seconds(60), cost: { _ in 1 }
        ) { _ in try await transport.load() }
        let first = Task { try await loader.image(for: url) }
        await transport.waitUntilStarted()
        first.cancel()
        _ = await first.result

        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await loader.image(for: url)
        }
        while !secondStarted { await Task.yield() }
        await transport.succeed("resumed")
        #expect(try await second.value == "resumed")
        #expect(await transport.callCount == 1)
    }

    @Test("캐시를 제거한 뒤에는 새 요청을 수행한다")
    func reloadsAfterEviction() async throws {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            return "cover"
        }
        _ = try await loader.image(for: url)
        loader.removeCachedImages()
        #expect(loader.cachedImage(for: url) == nil)
        _ = try await loader.image(for: url)
        #expect(calls == 2)
    }

    @Test("사전 로딩은 중복 URL을 제외한 다음 두 개만 받고 완료 캐시를 공유한다")
    func prefetchesOnlyTwoUniqueImages() async throws {
        let first = url
        let second = URL(string: "https://example.invalid/second")!
        let third = URL(string: "https://example.invalid/third")!
        var calls: [URL] = []
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { url in
            calls.append(url)
            return url.lastPathComponent
        }
        await loader.prefetch([first, first, second, third])
        #expect(Set(calls) == [first, second])
        #expect(loader.cachedImage(for: third) == nil)
        _ = try await loader.image(for: first)
        #expect(calls.count == 2)
    }
}

private actor ImageTransport {
    var callCount = 0
    private var cancellationCount = 0
    private var pending: CheckedContinuation<String, Error>?

    func load() async throws -> String {
        callCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func succeed(_ value: String) {
        pending?.resume(returning: value)
        pending = nil
    }

    private func cancel() {
        cancellationCount += 1
        pending?.resume(throwing: CancellationError())
        pending = nil
    }

    func waitUntilStarted(count: Int = 1) async {
        while callCount < count || pending == nil { await Task.yield() }
    }

    func waitUntilCancelled() async {
        while cancellationCount == 0 { await Task.yield() }
    }
}
