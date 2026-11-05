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
        assert(!ClaritySDK.calls.contains { $0.hasPrefix("tag:") })
        runtime.unprotect(protectedView)
        assert(ClaritySDK.calls.last == "resume")
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:build_channel:") }.count == 1)
        let consentIndex = ClaritySDK.calls.firstIndex(of: "consent:true")!
        let tagIndex = ClaritySDK.calls.firstIndex { $0.hasPrefix("tag:build_channel:") }!
        let resumeIndex = ClaritySDK.calls.firstIndex(of: "resume")!
        assert(consentIndex < tagIndex && tagIndex < resumeIndex)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("initialize:") }.count == 1)
        runtime.setActive(false)
        assert(ClaritySDK.calls.last == "pause")
        runtime.setActive(true)
        assert(ClaritySDK.calls.last == "resume")
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 1)

        // 비활성 중 새 세션 callback도 활성화될 때 태그를 한 번 설정한다.
        runtime.setActive(false)
        ClaritySDK.fireSessionStarted()
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 1)
        runtime.setActive(true)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 2)

        // 실패한 태그는 다음 허용된 apply에서 재시도하고 성공 후에는 반복하지 않는다.
        ClaritySDK.acceptsTags = false
        ClaritySDK.fireSessionStarted()
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 3)
        assert(!ClaritySDK.isPaused()) // 메타데이터 실패로 녹화를 차단하지 않음
        runtime.protect(protectedView)
        runtime.setActive(true)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 3)
        ClaritySDK.acceptsTags = true
        runtime.unprotect(protectedView)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 4)
        runtime.setActive(true)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == 4)
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

        // 철회 후 대기 태그는 다시 허용하고 SDK 동의까지 성공한 뒤에만 보낸다.
        runtime.protect(protectedView)
        runtime.saveConsent(enabled: true)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == tags)
        ClaritySDK.acceptsConsent = false
        runtime.unprotect(protectedView)
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == tags)
        assert(ClaritySDK.calls.filter { $0 == "resume" }.count == resumed)
        ClaritySDK.acceptsConsent = true
        let retryStart = ClaritySDK.calls.count
        runtime.setActive(true)
        let retried = Array(ClaritySDK.calls.dropFirst(retryStart))
        assert(retried.count == 3 && retried[0] == "consent:true"
            && retried[1].hasPrefix("tag:build_channel:") && retried[2] == "resume")
        assert(ClaritySDK.calls.filter { $0.hasPrefix("tag:") }.count == tags + 1)
        assert(SessionReplayConsent.storageKey != AnalyticsConsent.storageKey)
        print("Clarity consent, protected views, deferred tags, retries, background, revocation and restore checks passed")
    }
}
