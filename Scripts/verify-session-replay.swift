import Clarity
import Foundation

@main
enum SessionReplayProof {
    @MainActor static func main() throws {
        for chosen in [false, true] {
            for enabled in [false, true] {
                for active in [false, true] {
                    var policy = SessionReplayPolicy()
                    policy.consent = .init(enabled: enabled, hasChosen: chosen)
                    policy.isActive = active
                    assert(policy.shouldRecord == (chosen && enabled && active))
                    let first = UUID(), second = UUID()
                    policy.protect(first)
                    policy.protect(first)
                    policy.protect(second)
                    assert(!policy.shouldRecord)
                    policy.unprotect(first)
                    assert(!policy.shouldRecord) // 다른 보호 화면이 아직 남아 있음
                    policy.unprotect(second)
                    assert(policy.shouldRecord == (chosen && enabled && active))
                    let data = try JSONEncoder().encode(policy.consent)
                    let decoded = try JSONDecoder().decode(SessionReplayConsent.self, from: data)
                    assert(decoded == policy.consent)
                }
            }
        }
        let suite = "ClarityProof." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = SessionReplayRuntime(defaults: defaults)
        runtime.setActive(true)
        assert(ClaritySDK.calls.isEmpty) // 동의 전에는 SDK 초기화도 하지 않음
        let protectedView = UUID()
        runtime.protect(protectedView)
        runtime.saveConsent(enabled: true)
        assert(ClaritySDK.calls.isEmpty) // 동의 화면 자체는 수집하지 않음
        runtime.unprotect(protectedView)
        assert(ClaritySDK.calls.first == "initialize:z8n14vbcvp")
        assert(!ClaritySDK.calls.contains("resume")) // 비동기 준비 전 fail-closed
        runtime.protect(protectedView)
        ClaritySDK.fireSessionStarted()
        assert(!ClaritySDK.calls.contains("resume")) // 준비 도중 보호 화면에 들어옴
        assert(!ClaritySDK.calls.contains("consent:true"))
        runtime.unprotect(protectedView)
        assert(ClaritySDK.calls.last == "resume")
        assert(ClaritySDK.calls.filter { $0.hasPrefix("initialize:") }.count == 1)
        runtime.setActive(false)
        assert(ClaritySDK.calls.last == "pause")
        runtime.setActive(true)
        assert(ClaritySDK.calls.last == "resume")
        runtime.saveConsent(enabled: false)
        assert(ClaritySDK.calls.contains("consent:false"))
        let resumed = ClaritySDK.calls.filter { $0 == "resume" }.count
        let tags = ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count
        ClaritySDK.fireSessionStarted()
        assert(ClaritySDK.calls.filter { $0 == "resume" }.count == resumed)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == tags)
        assert(ClaritySDK.calls.last == "pause") // 철회 후 늦은 callback도 재개하지 않음
        let restored = SessionReplayRuntime(defaults: defaults)
        assert(restored.consent.hasChosen && !restored.consent.enabled)
        let count = ClaritySDK.calls.count
        restored.setActive(true)
        assert(ClaritySDK.calls.count == count)
        assert(SessionReplayConsent.storageKey != AnalyticsConsent.storageKey)
        print("Clarity consent, protected-view nesting, async startup, background, revocation and restore checks passed")
    }
}
