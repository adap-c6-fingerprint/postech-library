import Foundation
import Testing
import UIKit
@testable import fingerprint_library

@MainActor
struct RecommendationCoverPreparationTests {
    private func coverURL(_ number: Int) -> URL {
        URL(string: "https://example.com/cover/\(number).jpg")!
    }

    private func coveredBook(_ number: Int) -> Book {
        makeBook(number).replacingImageURL(coverURL(number))
    }

    private static let pngData = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).pngData { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
    }

    nonisolated private enum FakeFailure: Sendable {
        case server
        case brokenImage
        case offline

        var error: any Error {
            switch self {
            case .server: BookCoverFailure.httpStatus(500)
            case .brokenImage: BookCoverFailure.invalidImage
            case .offline: URLError(.notConnectedToInternet)
            }
        }
    }

    private func makePreparer(
        directory: URL,
        failures: [URL: FakeFailure]
    ) -> RecommendationCachePreparer {
        let data = Self.pngData
        return RecommendationCachePreparer(
            store: RecommendationCacheStore(directory: directory),
            loadCover: { url in
                if let failure = failures[url] { throw failure.error }
                return data
            },
            lookupYes24: { _ in nil }
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func collect(
        _ stream: AsyncThrowingStream<RecommendationPreparationEvent, Error>
    ) async -> (books: [Book], completed: CachedRecommendations?, offline: [Book]?, error: (any Error)?) {
        var books: [Book] = []
        var completed: CachedRecommendations?
        var offline: [Book]?
        do {
            for try await event in stream {
                switch event {
                case let .book(book, _): books.append(book)
                case let .completed(cached): completed = cached
                case let .offline(fallback): offline = fallback
                }
            }
            return (books, completed, offline, nil)
        } catch {
            return (books, completed, offline, error)
        }
    }

    @Test func 표지_확인된_책만_내보내고_스냅샷을_저장한다() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparer = makePreparer(
            directory: directory,
            failures: [coverURL(2): .server]
        )
        let candidates = (1...4).map(coveredBook)

        let result = await collect(preparer.prepareStream(candidates, count: 2))

        #expect(result.error == nil)
        #expect(result.books.count == 2)
        #expect(!result.books.contains { $0.id == coveredBook(2).id })
        #expect(result.completed?.books.map(\.id) == result.books.map(\.id))
        #expect(result.completed?.coverFiles.count == 2)
        let restored = try await RecommendationCacheStore(directory: directory).restore()
        #expect(restored?.books.map(\.id) == result.books.map(\.id))
    }

    @Test func 연결이_없으면_스냅샷을_저장하지_않고_offline으로_끝난다() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparer = makePreparer(
            directory: directory,
            failures: Dictionary(uniqueKeysWithValues: (2...4).map { (coverURL($0), FakeFailure.offline) })
        )

        let result = await collect(preparer.prepareStream((1...4).map(coveredBook), count: 3))

        #expect(result.books.map(\.id) == [coveredBook(1).id])
        #expect(result.completed == nil)
        #expect(result.error as? RecommendationPreparationError == .offline)
        let restored = try await RecommendationCacheStore(directory: directory).restore()
        #expect(restored == nil)
    }

    @Test func 다음_묶음은_표지_확인된_책만_돌려준다() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparer = makePreparer(
            directory: directory,
            failures: [coverURL(1): .brokenImage]
        )

        let books = try await preparer.verifyCovers((1...4).map(coveredBook), count: 3)

        #expect(Set(books.map(\.id)) == Set([2, 3, 4].map { coveredBook($0).id }))
    }

    @Test func 오프라인이면_보낸_책을_빼고_하드데이터로_남은_칸을_채운다() async {
        let shown = coveredBook(1)
        let cache = RecommendationCacheClient(
            restore: { nil },
            prepare: { CachedRecommendations(books: $0, savedAt: .distantPast, coverFiles: [:]) },
            prepareStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.book(shown, coverFile: URL(fileURLWithPath: "/tmp/1.image")))
                    continuation.finish(throwing: RecommendationPreparationError.offline)
                }
            }
        )
        let picks = (1...8).map(coveredBook)
        let client = HomeRecommendationForYouClient.live(
            recommendation: { count, _ in Array(picks.prefix(count)) },
            cache: cache,
            offlinePicks: { count in Array(picks.prefix(count)) }
        )

        let result = await collect(client.refresh(6, []))

        #expect(result.error == nil)
        #expect(result.books.map(\.id) == [shown.id])
        #expect(result.offline?.count == 5)
        #expect(result.offline?.contains { $0.id == shown.id } == false)
    }

    @Test func 연결_문제만_연결_없음으로_분류한다() {
        #expect(BookCoverFailure.isConnectionProblem(URLError(.notConnectedToInternet)))
        #expect(BookCoverFailure.isConnectionProblem(URLError(.timedOut)))
        #expect(!BookCoverFailure.isConnectionProblem(URLError(.badServerResponse)))
        #expect(!BookCoverFailure.isConnectionProblem(BookCoverFailure.httpStatus(500)))
        #expect(!BookCoverFailure.isConnectionProblem(BookCoverFailure.invalidImage))
    }
}
