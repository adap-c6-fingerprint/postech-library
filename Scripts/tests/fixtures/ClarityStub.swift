// SDK 호출 순서 검사용 대역. 실제 화면 수집이나 네트워크 요청은 하지 않는다.
import Foundation

public enum ClarityLogLevel: Equatable { case none, verbose }

@MainActor
public final class ClarityConfig {
    public let projectId: String
    public var logLevel = ClarityLogLevel.none
    public init(projectId: String) { self.projectId = projectId }
}

@MainActor
public enum ClaritySDK {
    public static var calls: [String] = []
    public static var acceptsInitialization = true
    public static var acceptsTags = true
    public static var acceptsConsent = true
    public static var acceptsCallbackRegistration = true
    public static var initializationLogLevel = ClarityLogLevel.none
    private static var paused = false
    private static var callback: ((String) -> Void)?

    public static func reset() {
        calls = []
        acceptsInitialization = true
        acceptsTags = true
        acceptsConsent = true
        acceptsCallbackRegistration = true
        initializationLogLevel = .none
        paused = false
        callback = nil
    }

    public static func initialize(config: ClarityConfig) -> Bool {
        calls.append("initialize:" + config.projectId)
        initializationLogLevel = config.logLevel
        return acceptsInitialization
    }
    public static func pause() { calls.append("pause"); paused = true }
    public static func resume() { calls.append("resume"); paused = false }
    public static func isPaused() -> Bool { paused }
    @discardableResult
    public static func setCustomTag(key: String, value: String) -> Bool {
        calls.append("tag:" + key + ":" + value)
        return acceptsTags
    }
    @discardableResult
    public static func consent(analyticsStorage: Bool) -> Bool {
        calls.append("consent:" + String(analyticsStorage))
        // 실제 SDK처럼 세션 시작 전에도 동의 신호를 접수한다.
        return acceptsConsent
    }
    @discardableResult
    public static func setOnSessionStartedCallback(_ value: @escaping (String) -> Void) -> Bool {
        guard acceptsCallbackRegistration else { return false }
        callback = value
        return true
    }
    public static func fireSessionStarted() { callback?("test-session") }
}
