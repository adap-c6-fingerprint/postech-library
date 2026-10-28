import Foundation
import Testing
@testable import fingerprint_library

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BookCoverModelTests {
    private let url = URL(string: "https://example.invalid/cover")!

    @Test("표지 주소 없음과 서버의 이미지 미제공을 기본 표지로 표시한다")
    func showsUnavailableCover() async {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            throw BookCoverFailure.unavailable(statusCode: 200)
        }
        let model = BookCoverModel(url: nil, pipeline: loader)
        await model.load(nil)
        if case .unavailable = model.phase(for: nil) {} else { Issue.record("주소 없음 상태가 아님") }
        #expect(calls == 0)
        await model.load(url)
        if case .unavailable = model.phase(for: url) {} else { Issue.record("미제공을 오류로 표시함") }
        #expect(calls == 1)
    }

    @Test("일시적 실패 뒤 같은 주소로 재시도하면 회복하고 완료 캐시를 재사용한다")
    func retriesTransientFailure() async {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return "recovered"
        }
        let model = BookCoverModel(url: url, pipeline: loader)
        await model.load(url)
        if case .failed = model.phase(for: url) {} else { Issue.record("전송 실패 상태가 아님") }
        await model.load(url)
        if case let .loaded(image) = model.phase(for: url) { #expect(image == "recovered") }
        else { Issue.record("재시도로 회복하지 못함") }
        await model.load(url)
        #expect(calls == 2)
    }

    @Test("손상된 이미지는 표지 없음으로 숨기지 않는다")
    func keepsInvalidImageRetryable() async {
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in throw BookCoverFailure.invalidImage }
        let model = BookCoverModel(url: url, pipeline: loader)
        await model.load(url)
        if case .failed = model.phase(for: url) {} else { Issue.record("손상 이미지를 미제공으로 숨김") }
    }

    @Test("미제공 결과를 영구 캐시하지 않아 다음 방문에서 새 표지를 받을 수 있다")
    func retriesUnavailableOnNextLoad() async {
        var calls = 0
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in
            calls += 1
            if calls == 1 { throw BookCoverFailure.unavailable(statusCode: 404) }
            return "new cover"
        }
        let model = BookCoverModel(url: url, pipeline: loader)
        await model.load(url)
        await model.load(url)
        if case let .loaded(image) = model.phase(for: url) { #expect(image == "new cover") }
        else { Issue.record("미제공 결과가 계속 유지됨") }
        #expect(calls == 2)
    }

    @Test("화면을 떠난 취소가 오류를 표시하거나 다음 책의 상태를 덮어쓰지 않는다")
    func ignoresCancelledLoad() async {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<String>.makeStream()
        let loader = SharedImageLoader<String>(cancellationDelay: .zero, cost: { _ in 1 }) { _ in
            started.continuation.yield()
            for await image in gate.stream { return image }
            throw CancellationError()
        }
        let model = BookCoverModel(url: url, pipeline: loader)
        let task = Task { await model.load(url) }
        for await _ in started.stream { break }
        task.cancel()
        await task.value
        if case .failed = model.phase(for: url) { Issue.record("화면 이탈 취소를 실패로 표시함") }
        await model.load(nil)
        gate.continuation.yield("late cover")
        gate.continuation.finish()
        if case .unavailable = model.phase(for: nil) {} else { Issue.record("늦은 응답이 다음 상태를 덮어씀") }
    }
}
