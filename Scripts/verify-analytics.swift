import Foundation

@main
enum AnalyticsProof {
    static func main() throws {
        // 동의·초기화·활성 상태의 모든 조합. 진단 단독 동의는 GA를 켜지 않는다.
        for chosen in [false, true] {
            for analytics in [false, true] {
                for diagnostics in [false, true] {
                    let consent = AnalyticsConsent(analytics: analytics, diagnostics: diagnostics, hasChosen: chosen)
                    for configured in [false, true] {
                        for active in [false, true] {
                            assert(consent.permitsEvents(configured: configured, active: active)
                                == (chosen && analytics && configured && active))
                        }
                    }
                    for eligible in [false, true] {
                        assert(consent.permitsDiagnosticReport(previousRunEligible: eligible)
                            == (chosen && diagnostics && eligible))
                    }
                    let data = try JSONEncoder().encode(consent)
                    let restored = try JSONDecoder().decode(AnalyticsConsent.self, from: data)
                    assert(restored == consent)
                }
            }
        }
        assert(AnalyticsConsent().analytics && AnalyticsConsent().diagnostics && AnalyticsConsent().hasChosen)
        var operations = AnalyticsOperations()
        let instant = ContinuousClock.now
        operations.start("old", at: instant)
        assert(operations.finish("old", at: instant.advanced(by: .milliseconds(1750))) == 1750)
        assert(operations.finish("old") == nil) // 중복 응답
        assert(operations.finish("never_started") == nil) // 동의 전 요청
        operations.start("cancelled", at: instant)
        _ = operations.finish("cancelled", at: instant)
        assert(operations.finish("cancelled") == nil) // 취소 후 늦은 응답
        operations.start("withdrawn", at: instant)
        operations.reset()
        assert(operations.finish("withdrawn") == nil) // 철회 후 재동의
        operations.start("a", at: instant)
        operations.start("b", at: instant.advanced(by: .milliseconds(10)))
        assert(operations.finish("a", at: instant.advanced(by: .milliseconds(20))) == 20)
        assert(operations.finish("b", at: instant.advanced(by: .milliseconds(20))) == 10)
        for index in 0..<101 { operations.start("bounded-\(index)", at: instant) }
        assert(operations.finish("bounded-0") == nil)
        assert(operations.finish("bounded-100", at: instant) == 0)

        func book(_ id: String, controlNumber: String? = nil) -> Book {
            Book(id: id, isbn: nil, controlNumber: controlNumber, title: "원문",
                 author: "원문", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        }
        assert(AnalyticsEvent.bookID(book("primo:alma1234")) == "alma1234")
        assert(AnalyticsEvent.bookID(book("primo:alma1234", controlNumber: "invalid")) == "alma1234")
        assert(AnalyticsEvent.bookID(book("primo:alma1234", controlNumber: "")) == "alma1234")
        assert(AnalyticsEvent.bookID(book("invalid", controlNumber: "primo:alma5678")) == "alma5678")
        assert(AnalyticsEvent.bookID(book("primo:alma1234", controlNumber: "alma5678")) == "alma5678")
        for invalid in ["alma", "alma１２３", "title:개인 입력", "alma1?query=private",
                        "almaprimo:123", "alma" + String(repeating: "1", count: 60)] {
            assert(AnalyticsEvent.bookID(book(invalid)) == "unknown")
        }
        let codes = AnalyticsEvent.Code.allCases.map(\.rawValue)
        assert(Set(codes).count == codes.count)
        assert(codes.allSatisfy { $0.count <= 40 && !$0.hasPrefix("firebase_") })
        print("Analytics consent matrix, report eligibility, request timing/cancellation, bounded storage and book-ID checks passed")
    }
}
