// SDK 호출 순서 검사용 대역. 실제 화면 수집이나 네트워크 요청은 하지 않는다.
import Foundation

@MainActor
public struct ClarityConfig {
    public let projectId: String
    public init(projectId: String) { self.projectId = projectId }
}

@MainActor
public enum ClaritySDK {
    public static var calls: [String] = []
    public static var acceptsInitialization = true
    private static var paused = false
    private static var callback: ((String) -> Void)?
    private static var ready = false

    public static func initialize(config: ClarityConfig) -> Bool {
        calls.append("initialize:" + config.projectId)
        return acceptsInitialization
    }
    public static func pause() { calls.append("pause"); paused = true }
    public static func resume() { calls.append("resume"); paused = false }
    public static func isPaused() -> Bool { paused }
    @discardableResult
    public static func setCustomTag(key: String, value: String) -> Bool {
        calls.append("tag:" + key + ":" + value)
        return true
    }
    @discardableResult
    public static func consent(analyticsStorage: Bool) -> Bool {
        calls.append("consent:" + String(analyticsStorage))
        return ready
    }
    @discardableResult
    public static func setOnSessionStartedCallback(_ value: @escaping (String) -> Void) -> Bool {
        callback = value
        return true
    }
    public static func fireSessionStarted() { ready = true; callback?("test-session") }
}
