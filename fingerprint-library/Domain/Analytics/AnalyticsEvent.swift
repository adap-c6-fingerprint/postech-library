import Foundation

nonisolated struct AnalyticsConsent: Codable, Equatable, Sendable {
    var analytics = true
    var diagnostics = true
    var hasChosen = true
    static let storageKey = "pobook.analytics.consent.v2"
    // 동의 화면이 없어졌으므로 시작하자마자 기본으로 수집한다. 키를 v2로 올려 예전 빌드에 저장된 선택(거부 포함)은 읽지 않는다.

    func permitsEvents(configured: Bool, active: Bool) -> Bool {
        hasChosen && analytics && configured && active
    }
    func permitsDiagnosticReport(previousRunEligible: Bool) -> Bool {
        hasChosen && diagnostics && previousRunEligible
    }
}

/// 자유 입력·좌표·층·서가 필드는 이 계약에 넣지 않는다.
nonisolated struct AnalyticsEvent: Equatable, Sendable {
    enum Code: String, CaseIterable, Sendable {
        case screenView = "screen_view"
        case appVisitStarted = "app_visit_started"
        case appActiveInterval = "app_active_interval"
        case screenActiveInterval = "screen_active_interval"
        case onboardingStarted = "onboarding_started"
        case onboardingCompleted = "onboarding_completed"
        case profileUpdated = "profile_updated"
        case searchSubmitted = "search_submitted"
        case searchCompleted = "search_completed"
        case searchFailed = "search_failed"
        case searchCancelled = "search_cancelled"
        case searchResultSelected = "search_result_selected"
        case bookDetailViewed = "book_detail_viewed"
        case bookFavoriteChanged = "book_favorite_changed"
        case cartBookAdded = "cart_book_added"
        case cartBooksRemoved = "cart_books_removed"
        case cartLimitBlocked = "cart_limit_blocked"
        case recommendationLoadCompleted = "recommendation_load_completed"
        case recommendationFailed = "recommendation_failed"
        case recommendationSelected = "recommendation_selected"
        case guidanceRequested = "guidance_requested"
        case routeCalculationStarted = "route_calculation_started"
        case routeCalculationCompleted = "route_calculation_completed"
        case routeCalculationFailed = "route_calculation_failed"
        case routeCalculationCancelled = "route_calculation_cancelled"
        case navigationStarted = "navigation_started"
        case navigationStepChanged = "navigation_step_changed"
        case navigationQualityChanged = "navigation_quality_changed"
        case destinationArrivalDetected = "destination_arrival_detected"
        case navigationCompleted = "navigation_completed"
        case navigationCancelled = "navigation_cancelled"
    }
    enum Field: String, Sendable {
        case operationID = "operation_id", navigationID = "navigation_id"
        case bookRecordID = "book_record_id", bookCount = "book_count"
        case resultCount = "result_count", removedCount = "removed_count"
        case cartCount = "cart_count", selectedCount = "selected_count"
        case cacheHit = "cache_hit", durationMS = "duration_ms"
        case kind, source, action
        case errorCode = "error_code"
        case stepIndex = "step_index", stopIndex = "stop_index"
        case distanceM = "distance_m", stepCount = "step_count"
        case qualityState = "quality_state", isTest = "is_test"
    }
    enum Value: Equatable, Sendable {
        case text(String), integer(Int), decimal(Double), flag(Bool)
    }
    let code: Code
    let fields: [Field: Value]
    init(_ code: Code, _ fields: [Field: Value] = [:]) {
        self.code = code
        self.fields = fields
    }

    static func bookID(_ book: Book) -> String {
        for id in [book.controlNumber, book.id].compactMap({ $0 }) {
            let raw = id.hasPrefix("primo:") ? String(id.dropFirst(6)) : id
            if raw.count <= 60, raw.hasPrefix("alma"), !raw.dropFirst(4).isEmpty,
               raw.dropFirst(4).allSatisfy({ $0.isASCII && $0.isNumber }) { return raw }
        }
        return "unknown"
    }
}

nonisolated enum AnalyticsScreen: String, Sendable {
    case map, recommendations, search, onboarding, detail, cart, favorites, myPage = "my_page"
    case routePreview = "route_preview", navigation, analyticsSettings = "analytics_settings"
}

/// 요청 세대와 함께 사용해 취소·늦은 응답·동의 변경을 중복 집계하지 않는다.
nonisolated struct AnalyticsOperations {
    private var starts: [String: ContinuousClock.Instant] = [:]

    mutating func start(_ id: String, at now: ContinuousClock.Instant = .now) {
        if starts.count >= 100 { starts.removeAll() }
        starts[id] = now
    }
    mutating func finish(_ id: String, at now: ContinuousClock.Instant = .now) -> Int? {
        guard let start = starts.removeValue(forKey: id) else { return nil }
        let duration = start.duration(to: now).components
        return max(0, Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000))
    }
    mutating func reset() {
        starts.removeAll()
    }
}
