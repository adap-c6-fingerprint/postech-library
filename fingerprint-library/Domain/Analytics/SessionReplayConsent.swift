import Foundation

nonisolated struct SessionReplayConsent: Codable, Equatable, Sendable {
    var enabled = true
    var hasChosen = true
    static let storageKey = "pobook.clarity.consent.v3"
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
