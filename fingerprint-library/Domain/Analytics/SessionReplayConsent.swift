import Foundation

/// GA 동의와 별도로 저장해 기존 분석 동의를 화면 녹화 동의로 해석하지 않는다.
nonisolated struct SessionReplayConsent: Codable, Equatable, Sendable {
    var enabled = true
    var hasChosen = true
    static let storageKey = "pobook.clarity.consent.v3"
    // 동의 화면이 없어 앱 시작부터 녹화한다. 키를 v3로 올려 예전 빌드에 저장된 선택(거부 포함)은 읽지 않는다.
}

nonisolated struct SessionReplayPolicy {
    var consent = SessionReplayConsent()
    var isActive = false
    private var protectedViews: Set<UUID> = []

    #if DEBUG
    var protectedViewCount: Int { protectedViews.count }
    #endif

    var shouldRecord: Bool {
        consent.hasChosen && consent.enabled && isActive && protectedViews.isEmpty
    }

    mutating func protect(_ token: UUID) { protectedViews.insert(token) }
    mutating func unprotect(_ token: UUID) { protectedViews.remove(token) }
}
