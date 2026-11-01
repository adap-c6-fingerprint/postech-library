import AppKit
import Foundation

/// 실제 서비스·캐시·표지 모델 소스를 함께 컴파일해 HTTP 경계를 검증한다.
@main
enum VerifyBookCoverFallback {
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
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

        let load: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { original in
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
        func check(_ label: String, url: URL?, isbn: String?, expected: String) async throws {
            let model = BookCoverModel(url: url, isbn: isbn, pipeline: loader,
                fallback: { try await resolver.coverURL(for: $0) })
            await model.load(url, isbn: isbn)
            let state: String
            switch model.phase(for: url, isbn: isbn) {
            case .loaded: state = "loaded"
            case .unavailable: state = "unavailable"
            case .failed: state = "failed"
            case .loading: state = "loading"
            }
            guard state == expected else { throw ProofError.failed("\(label): expected \(expected), got \(state)") }
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
            try await check("URL 누락", url: nil, isbn: "9788966260959", expected: "loaded")
            try await check("도서관 403 / ISBN10 정규화", url: base.appendingPathComponent("library/403"), isbn: "8937460777", expected: "loaded")
            try await check("도서관 404 / 캐시 재사용", url: base.appendingPathComponent("library/404"), isbn: "9788937460777", expected: "loaded")
            try await check("다른 판본 거부", url: nil, isbn: "9780131103627", expected: "unavailable")
            try await check("Yes24 미등록", url: nil, isbn: "9791185042022", expected: "unavailable")
            try await check("Yes24 표지 null", url: nil, isbn: "9788998244545", expected: "unavailable")
            try await check("Yes24 일시 장애", url: nil, isbn: "9788931022728", expected: "failed")
            try await check("Yes24 재시도", url: nil, isbn: "9788931022728", expected: "loaded")
            try await check("ISBN 누락", url: nil, isbn: nil, expected: "unavailable")
            let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("_stats"))
            let calls = try JSONDecoder().decode([String: Int].self, from: data)
            guard calls["9788937460777"] == 1, calls["9788931022728"] == 2, calls.count == 6 else {
                throw ProofError.failed("캐시·재시도 호출 횟수가 다릅니다")
            }
            print("PASS HTTP 요청 기록: ISBN별 중복 방지 및 실패 후 재시도 확인")
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw ProofError.failed(message) }
        return value
    }
    private enum ProofError: Error { case failed(String) }
}
