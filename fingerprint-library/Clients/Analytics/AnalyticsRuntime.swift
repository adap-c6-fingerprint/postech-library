import CryptoKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import StoreKit

/// SDK 호출·동의 변경을 같은 lock으로 순서화한다. 사용자 입력 원문은 받지 않는다.
nonisolated final class AnalyticsRuntime: @unchecked Sendable {
    static let shared = AnalyticsRuntime()
    static let consentChanged = Notification.Name("pobook.analytics.consent.changed")
    private let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private var storedConsent: AnalyticsConsent
    private var configured = false
    private var environment = "unknown"
    private var subjectID: String?
    private var visitID: String?
    private let launchID = UUID().uuidString
    private var lastInactive: ContinuousClock.Instant?
    private var active = false
    private var intervalStart: ContinuousClock.Instant?
    private var screens: [(UUID, AnalyticsScreen)] = []
    private var operations = AnalyticsOperations()
    private var lastNavigationState: [String: AnalyticsEvent] = [:]
    private var profileRevision = 0
    private var profileVersion: String?
    private static let diagnosticEligibilityKey = "pobook.diagnostics.report_eligible"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedConsent = defaults.data(forKey: AnalyticsConsent.storageKey)
            .flatMap { try? JSONDecoder().decode(AnalyticsConsent.self, from: $0) } ?? AnalyticsConsent()
        if !storedConsent.hasChosen { storedConsent = AnalyticsConsent() }
    }
    var consent: AnalyticsConsent { synchronized { storedConsent } }

    func start() {
        synchronized {
            guard !configured, FirebaseApp.app() != nil else { return }
            configured = true
            // 자동 보고를 켜면 철회 후 현재 실행의 전송을 통제할 수 없어 수동 보고만 사용한다.
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            // 실행 도중 처음 동의했거나 철회한 실행의 로컬 보고서는 소급 전송하지 않는다.
            if storedConsent.permitsDiagnosticReport(previousRunEligible: defaults.bool(forKey: Self.diagnosticEligibilityKey)) {
                Crashlytics.crashlytics().sendUnsentReports()
            }
            else { Crashlytics.crashlytics().deleteUnsentReports() }
            defaults.set(storedConsent.diagnostics, forKey: Self.diagnosticEligibilityKey)
            applySDKConsent()
        }
        #if targetEnvironment(simulator)
        setEnvironment("simulator")
        #elseif DEBUG
        setEnvironment("development")
        #else
        Task {
            let name: String
            do {
                switch try await AppTransaction.shared {
                case let .verified(transaction):
                    switch transaction.environment {
                    case .production: name = "production"
                    case .sandbox: name = "testflight"
                    case .xcode: name = "development"
                    default: name = "unknown"
                    }
                case .unverified: name = "unknown"
                }
            } catch { name = "unknown" }
            setEnvironment(name)
        }
        #endif
    }

    func saveConsent(_ choice: AnalyticsConsent) {
        synchronized {
            checkpointLocked()
            let previous = storedConsent
            storedConsent = AnalyticsConsent(analytics: choice.analytics, diagnostics: choice.diagnostics, hasChosen: true)
            defaults.set(try? JSONEncoder().encode(storedConsent), forKey: AnalyticsConsent.storageKey)
            profileRevision += 1
            operations.reset()
            lastNavigationState.removeAll()
            visitID = nil
            profileVersion = nil
            intervalStart = nil
            if previous.analytics && !choice.analytics, configured {
                Analytics.setAnalyticsCollectionEnabled(false)
                Analytics.setUserID(nil)
                Analytics.resetAnalyticsData()
                for key in ["affiliation_id", "interest_count"] { Analytics.setUserProperty(nil, forName: key) }
            }
            if !choice.analytics {
                subjectID = nil
                for key in ["pobook.analytics.subject", "pobook.analytics.profile_hash", "pobook.analytics.profile_version"] {
                    defaults.removeObject(forKey: key)
                }
            }
            if configured {
                if previous.diagnostics != choice.diagnostics || !choice.diagnostics {
                    Crashlytics.crashlytics().deleteUnsentReports()
                }
                if !choice.diagnostics {
                    defaults.set(false, forKey: Self.diagnosticEligibilityKey)
                    Crashlytics.crashlytics().setUserID("")
                    for key in ["screen_code", "last_action_code", "navigation_id", "visit_id", "launch_id"] {
                        Crashlytics.crashlytics().setCustomValue("", forKey: key)
                    }
                }
                applySDKConsent()
                if active { beginVisitIfNeeded() }
            }
        }
        NotificationCenter.default.post(name: Self.consentChanged, object: nil)
    }

    func setActive(_ value: Bool) {
        synchronized {
            guard active != value else { return }
            if !value { checkpointLocked(); lastInactive = .now }
            active = value
            if value { beginVisitIfNeeded() }
        }
    }
    func checkpoint() { synchronized { checkpointLocked() } }

    func showScreen(_ screen: AnalyticsScreen, token: UUID) {
        synchronized {
            guard !screens.contains(where: { $0.0 == token }) else { return }
            checkpointLocked()
            screens.append((token, screen))
            screenChanged()
        }
    }
    func hideScreen(token: UUID) {
        synchronized {
            guard let index = screens.firstIndex(where: { $0.0 == token }) else { return }
            let wasVisible = index == screens.count - 1
            if wasVisible { checkpointLocked() }
            screens.remove(at: index)
            if wasVisible { screenChanged() }
        }
    }

    func record(_ event: AnalyticsEvent) {
        synchronized {
            guard configured, active else { return }
            var parameters: [String: Any] = [:]
            for (field, value) in event.fields {
                switch value {
                case let .text(text): parameters[field.rawValue] = String(text.prefix(100))
                case let .integer(number): parameters[field.rawValue] = number
                case let .decimal(number): if number.isFinite { parameters[field.rawValue] = number }
                case let .flag(flag): parameters[field.rawValue] = flag ? "yes" : "no"
                }
            }
            if event.code == .navigationStepChanged || event.code == .navigationQualityChanged,
               let id = parameters["navigation_id"] as? String {
                let key = id + event.code.rawValue
                guard lastNavigationState[key] != event else { return }
                if lastNavigationState.count >= 100 { lastNavigationState.removeAll() }
                lastNavigationState[key] = event
            }
            if storedConsent.diagnostics {
                let crash = Crashlytics.crashlytics()
                crash.setCustomValue(event.code.rawValue, forKey: "last_action_code")
                crash.setCustomValue(parameters["navigation_id"] as? String ?? "", forKey: "navigation_id")
                // 원문 데이터 대신 코드만 breadcrumb에 남긴다.
                crash.log(event.code.rawValue)
            }
            guard storedConsent.permitsEvents(configured: configured, active: active) else { return }
            if let operation = parameters["operation_id"] as? String {
                switch event.code {
                case .searchSubmitted, .routeCalculationStarted:
                    operations.start(operation)
                case .searchCompleted, .searchFailed, .searchCancelled,
                     .routeCalculationCompleted, .routeCalculationFailed, .routeCalculationCancelled:
                    // 동의 전에 시작한 요청과 이미 끝난 요청을 소급·중복 집계하지 않는다.
                    guard let duration = operations.finish(operation) else { return }
                    parameters["duration_ms"] = duration
                default: break
                }
            }
            emit(event.code.rawValue, parameters)
        }
    }

    #if DEBUG
    var canRecordDiagnosticTest: Bool {
        synchronized {
            configured && storedConsent.diagnostics && defaults.bool(forKey: Self.diagnosticEligibilityKey)
        }
    }
    func recordDiagnosticTest() {
        synchronized {
            guard canRecordDiagnosticTest else { return }
            Crashlytics.crashlytics().record(error: NSError(
                domain: "PoBook.DiagnosticTest", code: 267,
                userInfo: [NSLocalizedDescriptionKey: "User requested a nonfatal diagnostic test"]
            ))
        }
    }
    #endif

    func updateProfile(_ profile: UserProfile?) {
        let revision: Int? = synchronized {
            guard configured, storedConsent.analytics else { return nil }
            profileRevision += 1
            return profileRevision
        }
        guard let revision else { return }
        Task {
            let affiliation = await AnalyticsAffiliationLookup.shared.id(for: profile?.affiliationKey)
            synchronized {
                guard storedConsent.analytics, profileRevision == revision else { return }
                let canonical = [profile?.affiliationKey.joined(separator: "\u{1f}") ?? "",
                                 profile?.interests.sorted().joined(separator: "\u{1f}") ?? ""]
                    .joined(separator: "\u{1e}")
                let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
                let changed = defaults.string(forKey: "pobook.analytics.profile_hash") != hash
                let version = changed ? UUID().uuidString
                    : defaults.string(forKey: "pobook.analytics.profile_version") ?? UUID().uuidString
                defaults.set(hash, forKey: "pobook.analytics.profile_hash")
                defaults.set(version, forKey: "pobook.analytics.profile_version")
                profileVersion = version
                Analytics.setUserProperty(affiliation ?? "unknown", forName: "affiliation_id")
                Analytics.setUserProperty(String(profile?.interests.count ?? 0), forName: "interest_count")
                if changed, active { emit("profile_updated", ["interest_count": profile?.interests.count ?? 0]) }
            }
        }
    }

    private func applySDKConsent() {
        Analytics.setConsent([.analyticsStorage: storedConsent.analytics ? .granted : .denied,
                              .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(storedConsent.analytics)
        if storedConsent.analytics {
            subjectID = defaults.string(forKey: "pobook.analytics.subject") ?? UUID().uuidString
            defaults.set(subjectID, forKey: "pobook.analytics.subject")
        }
        Analytics.setUserID(storedConsent.analytics ? subjectID : nil)
        if storedConsent.diagnostics {
            Crashlytics.crashlytics().setCustomValue(launchID, forKey: "launch_id")
            Crashlytics.crashlytics().setCustomValue(environment, forKey: "build_environment")
        }
    }
    private func setEnvironment(_ name: String) {
        synchronized {
            environment = name
            if configured {
                Analytics.setDefaultEventParameters(["build_environment": name])
                if storedConsent.diagnostics { Crashlytics.crashlytics().setCustomValue(name, forKey: "build_environment") }
            }
        }
    }
    private func beginVisitIfNeeded() {
        guard configured, storedConsent.analytics, active else { return }
        if visitID == nil || lastInactive.map({ milliseconds(since: $0) >= 1_800_000 }) == true {
            visitID = UUID().uuidString
            operations.reset()
            emit("app_visit_started", [:])
        }
        if storedConsent.diagnostics {
            Crashlytics.crashlytics().setCustomValue(visitID ?? "", forKey: "visit_id")
        }
        intervalStart = .now
        screenChanged()
    }
    private func screenChanged() {
        guard configured else { return }
        if storedConsent.diagnostics {
            Crashlytics.crashlytics().setCustomValue(screens.last?.1.rawValue ?? "unknown", forKey: "screen_code")
        }
        guard active, storedConsent.analytics else { return }
        if let screen = screens.last?.1 { emit("screen_view", ["screen_name": screen.rawValue]) }
        intervalStart = .now
    }
    private func checkpointLocked() {
        guard active, configured, storedConsent.analytics, let start = intervalStart else { return }
        let duration = milliseconds(since: start)
        if duration > 0 {
            emit("app_active_interval", ["duration_ms": duration])
            if let screen = screens.last?.1 {
                emit("screen_active_interval", ["duration_ms": duration, "screen_name": screen.rawValue])
            }
        }
        intervalStart = .now
    }
    private func emit(_ name: String, _ fields: [String: Any]) {
        guard configured, storedConsent.analytics else { return }
        var fields = fields
        fields["event_id"] = UUID().uuidString
        fields["visit_id"] = visitID
        fields["launch_id"] = launchID
        fields["profile_version_id"] = profileVersion
        fields["build_environment"] = environment
        Analytics.logEvent(name, parameters: fields)
    }
    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let components = start.duration(to: .now).components
        return max(0, Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000))
    }
    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private actor AnalyticsAffiliationLookup {
    static let shared = AnalyticsAffiliationLookup()
    private var values: [[String]: String]?
    func id(for key: [String]?) -> String? {
        guard let key else { return nil }
        if values == nil {
            nonisolated struct Catalog: Decodable { let affiliations: [Item] }
            nonisolated struct Item: Decodable { let id: String; let selectionKey: [String] }
            if let url = Bundle.main.url(forResource: "RecommendationDataset", withExtension: "json"),
               let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
                values = Dictionary(catalog.affiliations.map { ($0.selectionKey, $0.id) }, uniquingKeysWith: { first, _ in first })
            }
        }
        return values?[key]
    }
}
