import Foundation
import Testing
@testable import fingerprint_library

struct BookCoverFailureTests {
    private let url = URL(string: "https://example.invalid/cover")!

    @Test("공백만 있는 정상 응답도 이미지 미제공으로 처리한다")
    func recognizesWhitespaceOnlyBody() throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(throws: BookCoverFailure.unavailable(statusCode: 200)) {
            try BookCoverFailure.validate(data: Data(" \t\r\n".utf8), response: response)
        }
    }

    @Test("빈 정상 응답·204·404·410은 표지 미제공으로 분류한다", arguments: [200, 204, 404, 410])
    func recognizesUnavailable(status: Int) throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(throws: BookCoverFailure.unavailable(statusCode: status)) {
            try BookCoverFailure.validate(data: Data(), response: response)
        }
    }

    @Test("403·429·5xx는 빈 본문이어도 미제공으로 숨기지 않는다", arguments: [403, 429, 500, 503])
    func preservesServerFailures(status: Int) throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(throws: BookCoverFailure.httpStatus(status)) {
            try BookCoverFailure.validate(data: Data(), response: response)
        }
    }

    @Test("잘못된 Content-Type만으로 정상 이미지 데이터를 거부하지 않는다")
    func allowsImageDecodingToValidateNonemptyBody() throws {
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/octet-stream"]
        ))
        try BookCoverFailure.validate(data: RecommendationCacheFixture.image, response: response)
    }

    @Test("HTTP가 아닌 응답은 표지 미제공으로 처리하지 않는다")
    func rejectsNonHTTP() {
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: BookCoverFailure.invalidResponse) {
            try BookCoverFailure.validate(data: Data(), response: response)
        }
    }

    @Test("진단 값에는 원본 URL·오류 설명 없이 분류와 숫자만 담는다")
    func redactsDiagnostic() {
        let error = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: url])
        let diagnostic = BookCoverFailure.diagnostic(for: error)
        #expect(diagnostic == .init(reason: "transport", httpStatus: 0, transportCode: -1001))
        #expect(BookCoverFailure.diagnostic(for: BookCoverFailure.httpStatus(503)).httpStatus == 503)
        #expect(!BookCoverFailure.isUnavailable(BookCoverFailure.invalidImage))
    }
}
