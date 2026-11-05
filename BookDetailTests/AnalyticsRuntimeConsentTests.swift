import Foundation
import Testing
@testable import fingerprint_library

nonisolated struct AnalyticsRuntimeConsentTests {
    @Test("Firebase 미설정 실행의 진단 철회·재동의도 이전 보고서 전송 자격을 지운다")
    func withdrawalWithoutFirebase() throws {
        let suite = "AnalyticsRuntimeConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "pobook.diagnostics.report_eligible")
        let consent = AnalyticsConsent(analytics: true, diagnostics: true, hasChosen: true)
        defaults.set(try JSONEncoder().encode(consent), forKey: AnalyticsConsent.storageKey)
        let runtime = AnalyticsRuntime(defaults: defaults)
        runtime.saveConsent(.init(analytics: true, diagnostics: false, hasChosen: true))
        #expect(!defaults.bool(forKey: "pobook.diagnostics.report_eligible"))
        runtime.saveConsent(consent)
        let relaunched = AnalyticsRuntime(defaults: defaults)
        #expect(!relaunched.consent.permitsDiagnosticReport(
            previousRunEligible: defaults.bool(forKey: "pobook.diagnostics.report_eligible")
        ))
    }
}
