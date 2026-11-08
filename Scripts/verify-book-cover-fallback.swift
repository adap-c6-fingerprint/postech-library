import AppKit
import Foundation

/// 실제 서비스·캐시·표지 모델 소스를 함께 컴파일해 HTTP 경계를 검증한다.
@main
enum VerifyBookCoverFallback {
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.contains("--cache-only") {
            try await checkRecommendationCoverRecovery()
            return
        }
        let live = arguments.contains("--live")
        let base = URL(string: "http://127.0.0.1:4174/covers")!
        let token: String
        if live {
            let config = try String(contentsOfFile: "Secrets.xcconfig", encoding: .utf8)
            token = try require(config.split(separator: "\n").compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "POBOOK_RELAY_TOKEN_DEVELOPMENT" else { return nil }
                return parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }.first, "로컬 개발 중계 토큰이 필요합니다")
        } else { token = "local-proof-relay-token-with-at-least-32-characters" }

        let trace = RequestTrace()
        let load: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { original in
            if let path = original.url?.path { await trace.record(path) }
            var request = original
            if !live, let url = original.url, url.host != "127.0.0.1" {
                var routed = URLComponents(url: base, resolvingAgainstBaseURL: false)!
                routed.path += url.path.replacingOccurrences(of: "/yes24/v1/", with: "/v1/")
                routed.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
                request.url = routed.url
                if url.path.hasPrefix("/yes24/") {
                    // 로컬 공급자 mock만 가짜 제공사 키를 사용한다. 실제 앱은 중계 토큰만 보낸다.
                    request.setValue(nil, forHTTPHeaderField: "Authorization")
                    request.setValue("proof-key", forHTTPHeaderField: "X-Api-Key")
                }
            }
            return try await URLSession.shared.data(for: request)
        }
        let service = Yes24BookDetailService(relay: .init(httpClient: HTTPClient(load: load), configuration: {
            .init(environment: .development, token: token)
        }))
        let resolver = Yes24BookCoverResolver { try await service.fetchCoverURL(isbn13: $0) }
        let loader = SharedImageLoader<Data>(cost: { $0.count }) { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await load(request)
            try BookCoverFailure.validate(data: data, response: response)
            guard NSBitmapImageRep(data: data) != nil else { throw BookCoverFailure.invalidImage }
            return data
        }
        func check(
            _ label: String, url: URL?, isbn: String?, expected: String, expectedRequests: [String]? = nil
        ) async throws {
            let model = BookCoverModel(url: url, isbn: isbn, pipeline: loader,
                lookupYes24: { try await resolver.url(for: $0) })
            await model.load(url, isbn: isbn)
            let state: String
            switch model.phase(for: url, isbn: isbn) {
            case .loaded: state = "loaded"
            case .unavailable: state = "unavailable"
            case .failed: state = "failed"
            case .loading: state = "loading"
            }
            guard state == expected else { throw ProofError.failed("\(label): expected \(expected), got \(state)") }
            let paths = await trace.takePaths()
            if let expectedRequests, paths != expectedRequests {
                throw ProofError.failed("\(label): expected requests \(expectedRequests), got \(paths)")
            }
            print("PASS \(label): \(state)")
        }

        if live {
            // 도서관 응답에서 같은 ISBN으로 확인한 『1984』 5개 판본. 키·헤더는 출력하지 않는다.
            for isbn in ["9791185042022", "9788931022728", "9788964600955", "9788937460777", "9788998244545"] {
                let url = URL(string: "https://local.4libs.org/apps/summon/PrimoBookCover.php?isbn=\(isbn)&institute=82KC-P")!
                try await check("1984 ISBN \(isbn)", url: url, isbn: isbn, expected: "loaded")
            }
            try await check("ISBN 누락", url: nil, isbn: nil, expected: "unavailable")
        } else {
            let yes24Detail = "/yes24/v1/goods/itemDetail"
            let libraryCover = base.appendingPathComponent("library/200")
            try await check(
                "기존 YES24 주소 바로 사용", url: URL(string: "https://image.yes24.com/goods/123456/L"),
                isbn: "9788966260959", expected: "loaded", expectedRequests: ["/goods/123456/L"]
            )
            try await check(
                "YES24 우선 / ISBN10 정규화", url: base.appendingPathComponent("library/403"),
                isbn: "8937460777", expected: "loaded", expectedRequests: [yes24Detail, "/goods/372300/L"]
            )
            try await check(
                "ISBN 및 이미지 캐시 재사용", url: base.appendingPathComponent("library/404"),
                isbn: "9788937460777", expected: "loaded", expectedRequests: []
            )
            try await check(
                "YES24 미등록 시 도서관 표지", url: libraryCover,
                isbn: "9791185042022", expected: "loaded", expectedRequests: [yes24Detail, libraryCover.path]
            )
            try await check(
                "YES24 이미지 404 시 도서관 표지", url: libraryCover,
                isbn: "9780141036144", expected: "loaded", expectedRequests: [yes24Detail, "/goods/404/L"]
            )
            try await check("URL 누락", url: nil, isbn: "9788966260959", expected: "loaded")
            try await check("다른 판본 거부", url: nil, isbn: "9780131103627", expected: "unavailable")
            try await check("Yes24 미등록", url: nil, isbn: "9791185042022", expected: "unavailable")
            try await check("Yes24 표지 null", url: nil, isbn: "9788998244545", expected: "unavailable")
            try await check("Yes24 일시 장애", url: nil, isbn: "9788931022728", expected: "failed")
            try await check("Yes24 재시도", url: nil, isbn: "9788931022728", expected: "loaded")
            try await check("ISBN 누락", url: nil, isbn: nil, expected: "unavailable")
            let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("_stats"))
            let calls = try JSONDecoder().decode([String: Int].self, from: data)
            guard calls["9788937460777"] == 1, calls["9788931022728"] == 2, calls.count == 7 else {
                throw ProofError.failed("캐시·재시도 호출 횟수가 다릅니다")
            }
            print("PASS HTTP 요청 기록: ISBN별 중복 방지 및 실패 후 재시도 확인")
        }
    }

    @MainActor
    private static func checkRecommendationCoverRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RecommendationCacheStore(directory: directory)
        let original = URL(string: "https://library.example/cover.png")!
        let preferred = URL(string: "https://image.yes24.com/goods/1/L")!
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCw0AAAAASUVORK5CYII=")!
        let book = Book(
            id: "primo:alma1234567890", isbn: "9780140328721", controlNumber: "primo:alma1234567890",
            title: "Fixture", author: "Fixture", publisher: nil, publicationYear: nil,
            description: nil, imageURL: original
        )
        let preparer = RecommendationCachePreparer(
            store: cache, loadCover: { _ in png }, lookupYes24: { _ in preferred }
        )
        let saved = try await preparer.prepare([book])
        let file = try require(saved.coverFiles[book.id], "추천 로컬 표지가 없습니다")
        let restored = try require(try await cache.restore(), "추천 목록을 복원하지 못했습니다")
        guard saved.books.first?.imageURL == original, restored.books.first?.imageURL == original,
              restored.coverFiles[book.id] == file,
              try Data(contentsOf: file) == png else { throw ProofError.failed("원격 주소와 로컬 파일을 따로 보존해야 합니다") }

        let manifestURL = directory.appendingPathComponent("recommendations.json")
        let currentManifest = try Data(contentsOf: manifestURL)
        var legacyManifest = try require(
            try JSONSerialization.jsonObject(with: currentManifest) as? [String: Any], "추천 저장본 형식이 올바르지 않습니다"
        )
        var legacyBooks = try require(legacyManifest["books"] as? [[String: Any]], "추천 저장본에 도서가 없습니다")
        let legacySourceURL = legacyBooks[0].removeValue(forKey: "coverSourceURL")
        legacyBooks[0]["imageURL"] = legacySourceURL
        legacyManifest["version"] = 2
        legacyManifest["books"] = legacyBooks
        try JSONSerialization.data(withJSONObject: legacyManifest).write(to: manifestURL)
        let previous = try await cache.restore()
        guard previous?.books.first?.imageURL == preferred, previous?.coverFiles[book.id] == file else {
            throw ProofError.failed("이전 추천 저장본도 원격 주소와 로컬 파일을 복원해야 합니다")
        }
        try currentManifest.write(to: manifestURL)

        let loader = SharedImageLoader<Data>(cost: { $0.count }) { url in
            guard url == original else { throw BookCoverFailure.unreadableLocalFile }
            return png
        }
        try FileManager.default.removeItem(at: file)
        let fallback = try require(try await cache.restore(), "표지 파일 없이도 추천 목록이 남아야 합니다")
        guard fallback.coverFiles.isEmpty, fallback.books.first?.imageURL == original else {
            throw ProofError.failed("삭제한 파일 대신 원격 주소가 남아야 합니다")
        }
        let fresh = BookCoverModel(url: original, isbn: book.isbn, cachedURL: file, pipeline: loader)
        await fresh.load(original, isbn: book.isbn, cachedURL: file)
        guard case .loaded = fresh.phase(for: original, isbn: book.isbn, cachedURL: file) else {
            throw ProofError.failed("YES24 주소를 얻지 못해도 기존 원격 주소에서 표지를 불러와야 합니다")
        }
        let legacy = BookCoverModel(url: file, isbn: book.isbn, pipeline: loader)
        var repairedURL: URL?
        await legacy.load(file, isbn: book.isbn, lookupLegacyOriginal: { original }) { repairedURL = $0 }
        guard case .loaded = legacy.phase(for: file, isbn: book.isbn), repairedURL == original else {
            throw ProofError.failed("파일 경로만 있는 항목은 원격 표지를 읽은 뒤 주소를 갱신해야 합니다")
        }
        print("PASS 추천 원격 주소 보존, 로컬 표지 유실 폴백, 기존 파일 경로 복구")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw ProofError.failed(message) }
        return value
    }

    private actor RequestTrace {
        private var paths: [String] = []

        func record(_ path: String) { paths.append(path) }

        func takePaths() -> [String] {
            let result = paths
            paths.removeAll()
            return result
        }
    }

    private enum ProofError: Error { case failed(String) }
}
