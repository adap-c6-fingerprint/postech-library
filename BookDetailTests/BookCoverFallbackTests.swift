import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookCoverFallbackTests {
    private let isbn = "9788937460777"
    private let primary = URL(string: "https://library.example/1984")!
    private let secondary = URL(string: "https://image.yes24.com/goods/372300/L")!

    @Test("도서관 표지가 정상일 때 Yes24를 조회하지 않는다")
    func prefersLibraryCover() async {
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in "library" }
        let model = BookCoverModel(url: primary, isbn: isbn, pipeline: loader, fallback: { _ in
            Issue.record("정상 표지를 Yes24로 덮어쓰면 안 됩니다"); return nil
        })
        await model.load(primary, isbn: isbn)
        if case let .loaded(image) = model.phase(for: primary, isbn: isbn) { #expect(image == "library") }
        else { Issue.record("도서관 표지를 표시하지 못했습니다") }
    }

    @Test("URL 누락 또는 도서관 표지 로딩 실패 시 동일 ISBN의 Yes24 이미지를 가져온다", arguments: [0, 403, 404, 500])
    func loadsFallback(status: Int) async {
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { url in
            if url == self.primary { throw BookCoverFailure.httpStatus(status) }
            #expect(url == self.secondary)
            return "yes24"
        }
        let model = BookCoverModel(url: status == 0 ? nil : primary, isbn: "8937460777", pipeline: loader,
            fallback: { isbn in
                #expect(isbn == "9788937460777")
                return URL(string: "https://image.yes24.com/goods/372300/L")
            })
        await model.load(status == 0 ? nil : primary, isbn: "8937460777")
        if case let .loaded(image) = model.phase(for: status == 0 ? nil : primary, isbn: isbn) {
            #expect(image == "yes24")
        } else { Issue.record("Yes24 표지를 표시하지 못했습니다") }
    }

    @Test("ISBN이 없거나 잘못됐으면 표지 API를 호출하지 않는다", arguments: [nil, "9788937460770"] as [String?])
    func skipsUnknownIdentity(isbn: String?) async {
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in "unused" }
        let model = BookCoverModel(url: nil, isbn: isbn, pipeline: loader, fallback: { _ in
            Issue.record("유효한 ISBN 없이 판본을 추정하면 안 됩니다"); return nil
        })
        await model.load(nil, isbn: isbn)
        if case .unavailable = model.phase(for: nil, isbn: isbn) {} else { Issue.record("표지 없음 상태가 아닙니다") }
    }

    @Test("Yes24 미등록은 표지 없음, 통신 오류는 재시도 가능한 실패로 구분한다", arguments: [false, true])
    func distinguishesMissingAndFailure(fails: Bool) async {
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { _ in "unused" }
        let model = BookCoverModel(url: nil, isbn: isbn, pipeline: loader, fallback: { _ in
            if fails { throw URLError(.timedOut) }
            return nil
        })
        await model.load(nil, isbn: isbn)
        switch model.phase(for: nil, isbn: isbn) {
        case .failed: #expect(fails)
        case .unavailable: #expect(!fails)
        default: Issue.record("미등록/실패 상태를 구분하지 못했습니다")
        }
    }

    @Test("URL이 모두 nil인 다른 책으로 바뀌어도 이전 ISBN 응답이 새 표지를 덮어쓰지 않는다")
    func ignoresLateFallback() async {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { $0.lastPathComponent }
        let model = BookCoverModel(url: nil, isbn: isbn, pipeline: loader, fallback: { isbn in
            if isbn == "9788937460777" {
                started.continuation.yield()
                for await _ in gate.stream { break }
                return URL(string: "https://image.yes24.com/old")
            }
            return URL(string: "https://image.yes24.com/new")
        })
        let old = Task { await model.load(nil, isbn: isbn) }
        for await _ in started.stream { break }
        await model.load(nil, isbn: "9788966260959")
        gate.continuation.yield(); gate.continuation.finish()
        await old.value
        if case let .loaded(image) = model.phase(for: nil, isbn: "9788966260959") { #expect(image == "new") }
        else { Issue.record("이전 책의 늦은 응답이 새 책 상태를 덮어썼습니다") }
        if case .loading = model.phase(for: nil, isbn: isbn) {} else { Issue.record("다른 책의 표지를 잠깐 표시하면 안 됩니다") }
    }
}
