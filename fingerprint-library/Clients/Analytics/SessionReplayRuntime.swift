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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policy.consent = defaults.data(forKey: SessionReplayConsent.storageKey)
            .flatMap { try? JSONDecoder().decode(SessionReplayConsent.self, from: $0) }
            ?? SessionReplayConsent()
    }

    var consent: SessionReplayConsent { policy.consent }

    func saveConsent(enabled: Bool) {
        policy.consent = .init(enabled: enabled, hasChosen: true)
        defaults.set(try? JSONEncoder().encode(policy.consent), forKey: SessionReplayConsent.storageKey)
        apply()
    }

    func setActive(_ active: Bool) {
        policy.isActive = active
        apply()
    }

    func protect(_ token: UUID) {
        policy.protect(token)
        apply()
    }

    func unprotect(_ token: UUID) {
        policy.unprotect(token)
        apply()
    }

    private func apply() {
        if !initialized {
            // 동의 전에는 SDK 자체를 초기화하지 않는다.
            guard policy.shouldRecord else { return }
            initialized = ClaritySDK.initialize(config: ClarityConfig(projectId: "z8n14vbcvp"))
            guard initialized else {
                Logger(subsystem: "com.youngmin.fingerprint-library", category: "Clarity")
                    .error("Clarity initialization was not accepted.")
                return
            }
            ClaritySDK.pause()
            ClaritySDK.setOnSessionStartedCallback { [weak self] _ in
                guard let self else { return }
                self.ready = true
                if self.policy.shouldRecord {
                    #if targetEnvironment(simulator)
                    ClaritySDK.setCustomTag(key: "build_channel", value: "simulator")
                    #elseif DEBUG
                    ClaritySDK.setCustomTag(key: "build_channel", value: "development")
                    #else
                    ClaritySDK.setCustomTag(key: "build_channel", value: "release")
                    #endif
                }
                self.apply()
            }
        }
        guard ready else { ClaritySDK.pause(); return }
        let allowed = policy.consent.hasChosen && policy.consent.enabled
        if !allowed { ClaritySDK.pause() }
        if !allowed || policy.shouldRecord,
           appliedConsent != allowed, ClaritySDK.consent(analyticsStorage: allowed) {
            appliedConsent = allowed
        }
        if policy.shouldRecord, appliedConsent == true {
            if ClaritySDK.isPaused() { ClaritySDK.resume() }
        } else {
            ClaritySDK.pause()
        }
    }
}
