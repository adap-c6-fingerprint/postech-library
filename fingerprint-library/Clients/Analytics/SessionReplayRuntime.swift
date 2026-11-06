import Clarity
import Foundation
import OSLog

@MainActor
final class SessionReplayRuntime {
    static let shared = SessionReplayRuntime()
    private let defaults: UserDefaults
    private var policy = SessionReplayPolicy()
    private var initialized = false
    private var ready = false
    private var appliedConsent: Bool?
    private var needsBuildChannelTag = false

    private static var buildChannel: String {
        #if targetEnvironment(simulator)
        "simulator"
        #elseif DEBUG
        "development"
        #else
        "release"
        #endif
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policy.consent = defaults.data(forKey: SessionReplayConsent.storageKey)
            .flatMap { try? JSONDecoder().decode(SessionReplayConsent.self, from: $0) }
            ?? SessionReplayConsent()
        debugLog("consent_loaded")
    }

    var consent: SessionReplayConsent { policy.consent }

    func saveConsent(enabled: Bool) {
        policy.consent = .init(enabled: enabled, hasChosen: true)
        defaults.set(try? JSONEncoder().encode(policy.consent), forKey: SessionReplayConsent.storageKey)
        debugLog("consent_saved")
        apply()
    }

    func setActive(_ active: Bool) {
        policy.isActive = active
        debugLog("activity_changed")
        apply()
    }

    func protect(_ token: UUID) {
        policy.protect(token)
        debugLog("protected_view_added")
        apply()
    }

    func unprotect(_ token: UUID) {
        policy.unprotect(token)
        debugLog("protected_view_removed")
        apply()
    }

    private func apply() {
        if !initialized {
            // 동의 전에는 SDK 자체를 초기화하지 않는다.
            guard policy.shouldRecord else { debugLog("initialization_blocked_by_policy"); return }
            let config = ClarityConfig(projectId: "z8n14vbcvp")
            #if DEBUG
            config.logLevel = .verbose
            #endif
            debugLog("initialize_requested")
            initialized = ClaritySDK.initialize(config: config)
            debugLog("initialize_returned", result: initialized)
            guard initialized else {
                Logger(subsystem: "com.youngmin.fingerprint-library", category: "Clarity")
                    .error("Clarity initialization was not accepted.")
                return
            }
            ClaritySDK.pause()
            let registered = ClaritySDK.setOnSessionStartedCallback { [weak self] _ in
                guard let self else { return }
                self.ready = true
                self.needsBuildChannelTag = true
                self.debugLog("session_started")
                self.apply()
            }
            debugLog("session_callback_registered", result: registered)
        }
        guard ready else { ClaritySDK.pause(); debugLog("waiting_for_session"); return }
        let allowed = policy.consent.hasChosen && policy.consent.enabled
        if !allowed { ClaritySDK.pause() }
        if !allowed || policy.shouldRecord,
           appliedConsent != allowed {
            let accepted = ClaritySDK.consent(analyticsStorage: allowed)
            if accepted { appliedConsent = allowed }
            debugLog("sdk_consent_returned", result: accepted)
        }
        if policy.shouldRecord, appliedConsent == true {
            if needsBuildChannelTag {
                let tagged = ClaritySDK.setCustomTag(key: "build_channel", value: Self.buildChannel)
                if tagged { needsBuildChannelTag = false }
                debugLog("build_channel_tag_returned", result: tagged)
            }
            if ClaritySDK.isPaused() { ClaritySDK.resume() }
            debugLog("recording_allowed")
        } else {
            ClaritySDK.pause()
            debugLog("recording_blocked")
        }
    }

    private func debugLog(_ event: String, result: Bool? = nil) {
        #if DEBUG
        // 상태·개수만 기록하고 화면 내용·보호 토큰·세션 식별자는 출력하지 않는다.
        let paused = ready ? String(ClaritySDK.isPaused()) : "unknown"
        print("[ClarityDebug] event=\(event) result=\(result.map { String($0) } ?? "n/a") "
            + "has_chosen=\(policy.consent.hasChosen) consent_enabled=\(policy.consent.enabled) "
            + "active=\(policy.isActive) protected_views=\(policy.protectedViewCount) "
            + "policy_allows=\(policy.shouldRecord) initialized=\(initialized) ready=\(ready) "
            + "sdk_consent=\(appliedConsent.map { String($0) } ?? "unknown") sdk_paused=\(paused)")
        #endif
    }
}
