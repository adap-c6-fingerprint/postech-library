import Foundation
import Testing
@testable import fingerprint_library

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BookCoverRemoteLoaderTests {
    private let original = URL(string: "https://image.aladin.co.kr/product/243/94/cover/8954606334_1.jpg")!
    private let large = URL(string: "https://image.aladin.co.kr/product/243/94/cover500/8954606334_1.jpg")!

    @Test("큰 표지 주소는 동일 상품·파일명·쿼리를 보존하고 HTTPS를 사용한다", arguments: [
        ("https://image.aladin.co.kr/product/243/94/cover/8954606334_1.jpg?variant=1",
         "https://image.aladin.co.kr/product/243/94/cover500/8954606334_1.jpg?variant=1"),
        ("http://image.aladin.co.kr/product/27/61/cover/8970132538_1.gif",
         "https://image.aladin.co.kr/product/27/61/cover500/8970132538_1.gif"),
        ("https://image.yes24.com/goods/372300/L?variant=1",
         "https://image.yes24.com/goods/372300/XL?variant=1")
    ])
    func preservesBookIdentity(original: String, expected: String) throws {
        let url = try #require(URL(string: original))
        #expect(BookCoverRemoteLoader.largeURL(for: url)?.absoluteString == expected)
    }

    @Test("다른 공급자·이미 큰 표지·예상하지 못한 경로·로컬 파일은 바꾸지 않는다", arguments: [
        "https://covers.example.com/product/243/94/cover/book.jpg",
        "https://image.aladin.co.kr.example.com/product/243/94/cover/book.jpg",
        "https://image.aladin.co.kr/product/243/94/cover500/book.jpg",
        "https://image.aladin.co.kr/other/243/94/cover/book.jpg",
        "https://image.yes24.com/goods/372300/XL",
        "https://image.yes24.com/goods/372300/L/",
        "https://image.yes24.com/goods/372300/SIDE/L",
        "https://image.yes24.com/goods/not-a-product/L",
        "https://user:password@image.yes24.com/goods/372300/L",
        "file:///offline/cover/book.jpg"
    ])
    func keepsOtherURLsUnchanged(address: String) throws {
        #expect(BookCoverRemoteLoader.largeURL(for: try #require(URL(string: address))) == nil)
    }

    @Test("큰 표지에 성공하면 원본은 요청하지 않고 원본 URL의 공유 캐시로 재사용한다")
    func sharesPreferredCoverThroughExistingCache() async throws {
        var calls: [URL] = []
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { url in
            try await BookCoverRemoteLoader.image(for: url) { candidate in
                calls.append(candidate)
                return "large cover"
            }
        }
        #expect(try await loader.image(for: original) == "large cover")
        #expect(try await loader.image(for: original) == "large cover")
        #expect(loader.cachedImage(for: original) == "large cover")
        #expect(calls == [large])
    }

    @Test("큰 표지 미제공·전송 실패·손상 이미지는 원본 표지로 복구한다", arguments: [
        BookCoverFailure.unavailable(statusCode: 404), .httpStatus(403), .httpStatus(503), .invalidImage
    ])
    func fallsBackToOriginal(error: BookCoverFailure) async throws {
        var calls: [URL] = []
        let image = try await BookCoverRemoteLoader.image(for: original) { url in
            calls.append(url)
            if url == large { throw error }
            return "original cover"
        }
        #expect(image == "original cover")
        #expect(calls == [large, original])
    }

    @Test("큰 주소에서도 작은 정상 이미지가 반환되면 표지를 버리거나 재요청하지 않는다")
    func acceptsAvailableSmallCover() async throws {
        var calls: [URL] = []
        let smallCover = Cover(width: 102, height: 150)
        let image = try await BookCoverRemoteLoader.image(for: original) { url in
            calls.append(url)
            return smallCover
        }
        #expect(image.width == 102)
        #expect(image.height == 150)
        #expect(calls == [large])
    }

    @Test("지원하지 않는 공급자는 원본 주소를 한 번만 요청한다")
    func loadsOtherProviderOnce() async throws {
        let url = URL(string: "https://library.example/cover")!
        var calls: [URL] = []
        let image = try await BookCoverRemoteLoader.image(for: url) { candidate in
            calls.append(candidate)
            return "library cover"
        }
        #expect(image == "library cover")
        #expect(calls == [url])
    }

    @Test("큰 표지와 원본 모두 실패하면 원본 오류를 기존 ISBN 대체 처리에 전달한다")
    func preservesOriginalFailure() async {
        var calls: [URL] = []
        do {
            let _: String = try await BookCoverRemoteLoader.image(for: original) { url in
                calls.append(url)
                throw url == large ? BookCoverFailure.unavailable(statusCode: 404) : .httpStatus(503)
            }
            Issue.record("실패한 표지를 정상 처리했습니다")
        } catch {
            #expect(error as? BookCoverFailure == .httpStatus(503))
        }
        #expect(calls == [large, original])
    }

    @Test("도서관 큰 표지와 원본이 모두 실패하면 동일 ISBN의 Yes24 큰 표지를 표시한다")
    func connectsToExistingISBNFallback() async {
        var calls: [URL] = []
        let yes24 = URL(string: "https://image.yes24.com/goods/372300/L")!
        let yes24Large = URL(string: "https://image.yes24.com/goods/372300/XL")!
        let loader = SharedImageLoader<String>(cost: { _ in 1 }) { url in
            try await BookCoverRemoteLoader.image(for: url) { candidate in
                calls.append(candidate)
                if candidate == yes24Large { return "Yes24 large cover" }
                throw BookCoverFailure.unavailable(statusCode: 404)
            }
        }
        let model = BookCoverModel(url: original, isbn: "9788937460777", pipeline: loader,
                                   fallback: { isbn in
            #expect(isbn == "9788937460777")
            return URL(string: "https://image.yes24.com/goods/372300/L")
        })
        await model.load(original, isbn: "9788937460777")
        if case let .loaded(image) = model.phase(for: original, isbn: "9788937460777") {
            #expect(image == "Yes24 large cover")
        } else {
            Issue.record("기존 ISBN 대체 조회가 큰 표지 요청과 연결되지 않았습니다")
        }
        #expect(calls == [large, original, yes24Large])
        #expect(loader.cachedImage(for: yes24) == "Yes24 large cover")
    }

    @Test("취소 오류가 발생하면 원본 표지를 추가로 요청하지 않는다", arguments: [false, true])
    func doesNotFallbackAfterCancellation(transportCancellation: Bool) async {
        var calls: [URL] = []
        do {
            let _: String = try await BookCoverRemoteLoader.image(for: original) { url in
                calls.append(url)
                if transportCancellation { throw URLError(.cancelled) }
                throw CancellationError()
            }
            Issue.record("취소한 요청이 성공했습니다")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(calls == [large])
    }

    @Test("실제 Task 취소 뒤 늦게 성공한 다운로드도 반환하거나 원본으로 재요청하지 않는다")
    func ignoresCompletionAfterTaskCancellation() async {
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<String, Never>?
        var calls: [URL] = []
        let request = Task {
            try await BookCoverRemoteLoader.image(for: original) { url in
                calls.append(url)
                return await withCheckedContinuation { continuation in
                    pending = continuation
                    started.continuation.yield()
                }
            }
        }
        for await _ in started.stream { break }
        request.cancel()
        pending?.resume(returning: "late cover")
        do {
            _ = try await request.value
            Issue.record("취소 후 완료된 표지를 반환했습니다")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(calls == [large])
        started.continuation.finish()
    }
}

private nonisolated struct Cover: Sendable {
    let width: Int
    let height: Int
}
