import Foundation

// 이벤트명(Code), 파라미터키(Field), 화면이름(AnalyticsScreen)

nonisolated struct AnalyticsConsent: Codable, Equatable, Sendable {
    var analytics = true
    var diagnostics = true
    var hasChosen = true
    static let storageKey = "pobook.analytics.consent.v2"

    func permitsEvents(configured: Bool, active: Bool) -> Bool {
        hasChosen && analytics && configured && active
    }
    func permitsDiagnosticReport(previousRunEligible: Bool) -> Bool {
        hasChosen && diagnostics && previousRunEligible
    }
}

nonisolated struct AnalyticsEvent: Equatable, Sendable {
    enum Code: String, CaseIterable, Sendable {
        // case 코드상변수명 = "Firebase로_전송되는_변수명" // 의미
        // 변수명이 한 단어다? 그러면 그냥 파베에도 똑같이 전송됨
        
        // [유저 고유값]
        case profileUpdated = "profile_updated"
        // 소속·관심사 설정이 실제로 바뀜 (자동 전송, interest_count)

        // [책 RecordID 관련]
        case searchResultSelected = "search_result_selected"
        // 검색 화면에서 책 선택 (source = results 또는 recent)
        case bookDetailViewed = "book_detail_viewed"
        // 책 상세 화면 진입 (book_record_id)
        case bookFavoriteChanged = "book_favorite_changed"
        // 찜 추가·해제 (action = added 또는 removed)
        case cartBookAdded = "cart_book_added"
        // 장바구니에 책이 실제로 담김 (book_record_id)
        case recommendationSelected = "recommendation_selected"
        // 추천 탭에서 책 선택 (book_record_id)
        case cartBookRemoved = "cart_book_removed"
        // 장바구니 삭제 확정 시 삭제한 책마다 한 줄 (operation_id로 cart_books_removed와 연결)
        case favoriteBookRemoved = "favorite_book_removed"
        // 읽고 싶은 책 삭제 시 삭제한 책마다 한 줄 (operation_id로 book_favorite_changed와 연결)
        case routeBookIncluded = "route_book_included"
        // 길안내 경로 요청에 포함된 책마다 한 줄 (operation_id로 guidance_requested와 연결, stop_index)

        // [개별 액션 > 앱·화면] AnalyticsRuntime이 자동 전송
        case screenView = "screen_view"
        // 화면이 보임 (AnalyticsRuntime이 자동 전송, screen_name 포함)
        case appVisitStarted = "app_visit_started"
        // 새 방문 시작 (처음 실행 또는 30분 이상 비활성 후 복귀, 자동 전송)
        case appActiveInterval = "app_active_interval"
        // 앱을 켜 두고 사용한 시간 구간 (비활성 전환·화면 전환 시 자동 전송, duration_ms)
        case screenActiveInterval = "screen_active_interval"
        // 한 화면에 머문 시간 구간 (자동 전송, screen_name·duration_ms)

        // [개별 액션 > 온보딩]
        case onboardingStarted = "onboarding_started"
        // 온보딩 시작하기 버튼 누름
        case onboardingCompleted = "onboarding_completed"
        // 온보딩 완료 (selected_count = 고른 관심사 수)

        // [개별 액션 > 검색]
        case searchSubmitted = "search_submitted"
        // 검색어 제출 (operation_id로 완료·실패·취소와 연결)
        case searchCompleted = "search_completed"
        // 검색 결과 받음 (result_count, cache_hit, duration_ms)
        case searchFailed = "search_failed"
        // 검색 요청 실패 (error_code)
        case searchCancelled = "search_cancelled"
        // 결과가 오기 전에 검색 취소

        // [개별 액션 > 장바구니]
        case cartBooksRemoved = "cart_books_removed"
        // 장바구니에서 선택한 책 삭제 확정 (removed_count)
        case cartLimitBlocked = "cart_limit_blocked"
        // 장바구니가 가득 차 담기 실패 (kind = capacity)

        // [개별 액션 > 추천]
        case recommendationLoadCompleted = "recommendation_load_completed"
        // 추천 목록 준비 완료 (kind = restored·carousel_refresh·prepared_for_next_visit, book_count)
        case recommendationFailed = "recommendation_failed"
        // 추천 목록 준비 실패 (error_code)

        // [개별 액션 > 경로 계산] 길안내 미리보기
        case guidanceRequested = "guidance_requested"
        // 길안내 미리보기에서 경로 요청 시작 (book_count = 안내할 책 수)
        case routeCalculationStarted = "route_calculation_started"
        // 경로 계산 시작
        case routeCalculationCompleted = "route_calculation_completed"
        // 경로 계산 성공 (distance_m, step_count, duration_ms)
        case routeCalculationFailed = "route_calculation_failed"
        // 경로 계산 실패 (error_code)
        case routeCalculationCancelled = "route_calculation_cancelled"
        // 경로 계산 도중 취소

        // [개별 액션 > 실시간 길안내]
        case navigationStarted = "navigation_started"
        // 실시간 길안내 시작 (navigation_id, book_count, distance_m)
        case navigationStepChanged = "navigation_step_changed"
        // 길안내 단계가 다음으로 바뀜 (step_index, stop_index)
        case navigationQualityChanged = "navigation_quality_changed"
        // 위치 인식 상태가 바뀜 (quality_state)
        case destinationArrivalDetected = "destination_arrival_detected"
        // 현재 책의 서가 도착 감지 (stop_index)
        case navigationCompleted = "navigation_completed"
        // 길안내를 끝까지 마침
        case navigationCancelled = "navigation_cancelled"
        // 길안내를 도중에 종료 (stop_index = 종료 시점의 책 순서)

        // [개별 액션 > 버튼] 의미가 따로 없는 UI 조작은 모두 이 이벤트 하나로 보내고 button_id로 구분
        case buttonTapped = "button_tapped"
        // UI 버튼 누름 (button_id, screen_name, 책 관련 버튼이면 book_record_id)

        // [개별 액션 > 스크롤] 손가락을 뗀 순간 1회로 센다
        case scrollPerformed = "scroll_performed"
        // 스크롤·스와이프 1회 (screen_name, scroll_area, direction)
    }
    enum Field: String, Sendable {
        // 파라미터키
        // [유저 고유값]
        case selectedCount = "selected_count"
        // 온보딩에서 고른 관심사 개수
        case cartCount = "cart_count"
        // 장바구니 책 권수 (정의만 있고 현재 보내는 곳 없음)

        // [책 RecordID]
        case bookRecordID = "book_record_id"
        // 책 ID (primo: 접두사를 뗀 alma 번호, 형식이 맞지 않으면 unknown)
        case bookIDStatus = "book_id_status"
        // 책 ID 상태 (ok, invalid_format = 형식이 맞지 않아 unknown, missing = ID 없음)

        // [개별 액션 > 묶음 ID] 같은 동작에서 나온 이벤트들을 연결
        case operationID = "operation_id"
        // 한 번의 검색·경로 계산에서 나온 이벤트들을 묶는 ID (시작~완료 소요 시간 계산에도 사용)
        case navigationID = "navigation_id"
        // 한 번의 실시간 길안내에서 나온 이벤트들을 묶는 ID

        // [개별 액션 > 개수]
        case bookCount = "book_count"
        // 책 권수 (안내할 책 수, 추천 목록 수, 찜 삭제 수 등)
        case resultCount = "result_count"
        // 검색 결과 개수
        case removedCount = "removed_count"
        // 장바구니에서 삭제한 책 권수

        // [개별 액션 > 공통 구분값] 여러 이벤트에서 함께 쓰는 키
        case kind
        // 종류 구분값 (추천 준비 방식, 장바구니 담기 실패 이유 등)
        case source
        // 어디서 일어났는지 (검색: results = 검색 결과, recent = 최근 항목)
        case action
        // 무엇을 했는지 (찜: added = 추가, removed = 해제)
        case errorCode = "error_code"
        // 실패 원인 코드

        // [개별 액션 > 시간] 검색·경로 계산 소요 시간, 앱·화면 체류 시간
        case durationMS = "duration_ms"
        // 걸린 시간·머문 시간 (밀리초)

        // [개별 액션 > 검색 결과]
        case cacheHit = "cache_hit"
        // 검색 결과를 저장해 둔 결과에서 가져왔는지 (yes/no)

        // [개별 액션 > 실시간 길안내·경로]
        case stepIndex = "step_index"
        // 길안내 단계 번호
        case stopIndex = "stop_index"
        // 안내 중인 책 순서 (0부터 시작)
        case distanceM = "distance_m"
        // 경로 전체 길이 (미터)
        case stepCount = "step_count"
        // 경로의 안내 단계 수
        case qualityState = "quality_state"
        // 위치 인식 상태 (unknown_floor, ambiguous_position, off_route, unusable_position)
        case isTest = "is_test"
        // 테스트용 재생(replay) 경로인지 (yes/no)

        // [개별 액션 > 버튼·화면]
        case buttonID = "button_id"
        // 누른 버튼 (ButtonID 값)
        case screenName = "screen_name"
        // 이벤트가 일어난 화면 (AnalyticsScreen 값)

        // [개별 액션 > 스크롤]
        case direction
        // 스크롤·스와이프 방향 (up, down, left, right)
        case scrollArea = "scroll_area"
        // 한 화면에 스크롤 영역이 여럿일 때 어느 영역인지 (예: home, personal, bottom_sheet)

        // [개별 액션 > 지도]
        case floor
        // 층 번호 (지도 층 전환 버튼)
    }
    enum ButtonID: String, Sendable {
        // button_tapped의 button_id 값. 같은 의미의 버튼은 화면이 달라도 같은 값을 쓰고, 화면은 screen_name으로 구분한다
        // [책 RecordID > 장바구니·읽고 싶은 책]
        case bookSelect = "book_select"
        // 목록에서 책 선택 (체크)
        case bookDeselect = "book_deselect"
        // 목록에서 책 선택 해제

        // [책 RecordID > 지도]
        case favoriteMarker = "favorite_marker"
        // 지도에서 찜한 책 아이콘 탭

        // [책 RecordID > 상세·길안내 미리보기]
        case directGuidance = "direct_guidance"
        // 바로 안내 시작
        case cartNoticeLater = "cart_notice_later"
        // 장바구니 담은 뒤 알림 → 나중에
        case cartNoticeGo = "cart_notice_go"
        // 장바구니 담은 뒤 알림 → 바로가기
        case bookChip = "book_chip"
        // 길안내 미리보기 상단 책 칩으로 책 변경

        // [책 RecordID > 최근 찾은 책]
        case book
        // 최근 찾은 책 목록에서 책 탭

        // [책 RecordID > 실시간 길안내]
        case close
        // 길안내 X 버튼
        case previousShelf = "previous_shelf"
        // 이전 서가
        case shelfFound = "shelf_found"
        // 서가를 찾았어요
        case floorMove = "floor_move"
        // 000으로 층 이동하기
        case exitAlertReturn = "exit_alert_return"
        // 안내 종료 알림 → 돌아가기
        case exitAlertNextBook = "exit_alert_next_book"
        // 안내 종료 알림 → 다음 책 찾기
        case exitAlertEnd = "exit_alert_end"
        // 안내 종료 알림 → 안내 종료하기

        // [책 RecordID > 책등으로 책 찾기]
        case spineFound = "spine_found"
        // 찾았어요
        case spineNotFound = "spine_not_found"
        // 못 찾았어요
        case helpNextAndDesk = "help_next_and_desk"
        // 못 찾았어요 페이지 → 다음 책 찾고 대출 데스크로 안내 받기
        case helpLater = "help_later"
        // 못 찾았어요 페이지 → 다음에 찾기

        // [개별 액션 > 전역] 여러 화면에 공통으로 있는 버튼
        case back
        // 뒤로가기 (모든 화면 공통)
        case bookmark
        // 상단 북마크(읽고 싶은 책) 버튼
        case cart
        // 상단 장바구니 버튼
        case myPage = "my_page"
        // 상단 마이페이지 버튼
        case tabHome = "tab_home"
        // 하단 홈(지도) 탭
        case tabRecommendations = "tab_recommendations"
        // 하단 추천 탭
        case search
        // 하단 검색 버튼

        // [개별 액션 > 온보딩]
        case affiliationSelect = "affiliation_select"
        // 소속 대분류 선택
        case departmentSelect = "department_select"
        // 학과(세부 소속) 선택
        case affiliationCancel = "affiliation_cancel"
        // 소속 선택 안 하고 닫기
        case departmentCancel = "department_cancel"
        // 학과 선택 안 하고 닫기
        case later
        // 다음에 할래요
        case skipConfirmSetup = "skip_confirm_setup"
        // 건너뛰기 알림 → 설정하기
        case skipConfirmSkip = "skip_confirm_skip"
        // 건너뛰기 알림 → 건너뛰기
        case next
        // 다음으로
        case interestSelect = "interest_select"
        // 관심사 선택 (온보딩·관심 분야 변경 공통)
        case interestDeselect = "interest_deselect"
        // 관심사 선택 해제 (온보딩·관심 분야 변경 공통)
        case done
        // 선택 완료

        // [개별 액션 > 지도]
        case amenityToggle = "amenity_toggle"
        // 편의시설 켜기/끄기 (action = on, off)
        case floorSwitch = "floor_switch"
        // 층 전환 (floor)
        case myLocation = "my_location"
        // 내 위치 버튼

        // [개별 액션 > 추천]
        case recommendationRefresh = "recommendation_refresh"
        // 개인 추천도서 새로고침
        case departmentMore = "department_more"
        // '000'에서 많이 빌린 책 더보기

        // [개별 액션 > 장바구니·읽고 싶은 책]
        case delete
        // 선택한 책 삭제 버튼 (휴지통)
        case deleteCancel = "delete_cancel"
        // 삭제 알림 → 취소
        case deleteConfirm = "delete_confirm"
        // 삭제 알림 → 삭제 확정
        case addToCart = "add_to_cart"
        // 읽고 싶은 책 → 장바구니 담기
        case startGuidance = "start_guidance"
        // 장바구니 → 안내 시작하기 (book_count)

        // [개별 액션 > 검색 결과]
        case filterAll = "filter_all"
        // 전체 탭
        case filterBook = "filter_book"
        // 단행본 탭
        case filterJournal = "filter_journal"
        // 학술지 탭

        // [개별 액션 > 마이페이지]
        case recentMore = "recent_more"
        // 최근 찾은 책 더보기
        case editAffiliation = "edit_affiliation"
        // 소속 및 학과 정보 변경
        case editInterests = "edit_interests"
        // 관심분야 변경하기
        case locationPermission = "location_permission"
        // 위치 권한 설정
        case privacyPolicy = "privacy_policy"
        // 개인정보 처리방침
        case affiliationChange = "affiliation_change"
        // 소속 변경 화면 → 소속 변경
        case departmentChange = "department_change"
        // 소속 변경 화면 → 학과 변경
        case applyChange = "apply_change"
        // 소속 변경 화면 → 변경하기

        // [개별 액션 > 길안내 미리보기·위치 정하기]
        case locationAlertDeny = "location_alert_deny"
        // 위치 권한 알림 → 동의 안 함
        case locationAlertSettings = "location_alert_settings"
        // 위치 권한 알림 → 설정으로 이동
        case originCancel = "origin_cancel"
        // 위치 정하기 → 취소 및 삭제
        case originConfirm = "origin_confirm"
        // 위치 정하기 → 위치 확정하고 안내 받기
    }
    enum Value: Equatable, Sendable {
        case text(String)
        // 글자 값
        case integer(Int)
        // 정수 값
        case decimal(Double)
        // 소수 값 (무한대·NaN이면 보내지 않음)
        case flag(Bool)
        // 참/거짓 값 (Firebase에는 "yes"/"no" 글자로 보냄)
    }
    let code: Code
    // 이벤트 이름
    let fields: [Field: Value]
    // 파라미터 (키 = 값)
    init(_ code: Code, _ fields: [Field: Value] = [:]) {
        // 이벤트 이름과 파라미터로 이벤트 하나를 만든다
        self.code = code
        self.fields = fields
    }

    static func bookID(_ book: Book) -> String {
        // 책에서 분석용 책 ID를 꺼낸다 (controlNumber → id 순서로 확인, alma+숫자 형식이 아니면 "unknown")
        for id in [book.controlNumber, book.id].compactMap({ $0 }) {
            let raw = id.hasPrefix("primo:") ? String(id.dropFirst(6)) : id
            if raw.count <= 60, raw.hasPrefix("alma"), !raw.dropFirst(4).isEmpty,
               raw.dropFirst(4).allSatisfy({ $0.isASCII && $0.isNumber }) { return raw }
        }
        return "unknown"
    }

    static func bookIDStatus(_ book: Book) -> String {
        // 책 ID 상태를 정한다 (ok, invalid_format = 형식이 맞지 않아 unknown, missing = ID 없음)
        let ids = [book.controlNumber, book.id].compactMap { $0 }.filter { !$0.isEmpty }
        // 비어 있지 않은 ID 후보 (controlNumber → id 순서)
        if ids.isEmpty { return "missing" }
        return bookID(book) == "unknown" ? "invalid_format" : "ok"
    }

    static func bookFields(_ book: Book) -> [Field: Value] {
        // 책 이벤트에 넣는 파라미터 묶음 (book_record_id, book_id_status)
        [.bookRecordID: .text(bookID(book)), .bookIDStatus: .text(bookIDStatus(book))]
    }

    static func button(_ id: ButtonID, on screen: AnalyticsScreen, book: Book? = nil,
                       _ extra: [Field: Value] = [:]) -> AnalyticsEvent {
        // button_tapped 이벤트를 만든다 (button_id, screen_name, 책 버튼이면 책 파라미터, 추가 파라미터)
        var fields: [Field: Value] = [.buttonID: .text(id.rawValue), .screenName: .text(screen.rawValue)]
        if let book { fields.merge(bookFields(book)) { $1 } }
        // 책 관련 버튼이면 책 ID와 상태를 붙인다
        fields.merge(extra) { $1 }
        // 추가 파라미터를 합친다 (같은 키면 추가 값이 우선)
        return AnalyticsEvent(.buttonTapped, fields)
    }
}

nonisolated enum AnalyticsScreen: String, Sendable {
    case map, recommendations, search, onboarding, detail, cart, favorites, myPage = "my_page"
    case routePreview = "route_preview", navigation, analyticsSettings = "analytics_settings"

    // [issue540 추가 화면]
    case onboardingWelcome = "onboarding_welcome"
    // 온보딩 시작하기 화면
    case onboardingAffiliation = "onboarding_affiliation"
    // 온보딩 소속·학과 설정 화면
    case onboardingInterests = "onboarding_interests"
    // 온보딩 관심사 설정 화면
    case myPageInterests = "my_page_interests"
    // 마이페이지 → 관심 분야 변경 화면 (OnboardingView 재사용)
    case editAffiliation = "edit_affiliation"
    // 마이페이지 → 소속 및 학과 변경 화면 (EditMyAffiliationView)
    case recentlyFoundBooks = "recently_found_books"
    // 마이페이지 → 최근 찾은 책 목록 (RecentlyFoundBookView)
    case departmentRecommendations = "department_recommendations"
    // '000'에서 많이 빌린 책 (DepartmentRecommendationsView)
    case searchResults = "search_results"
    // 검색 결과 (검색 전 최근 항목은 기존 search)
    case routeOriginPicker = "route_origin_picker"
    // 위치 정하기 (BookRouteOriginPickerView)
    case spineFinding = "spine_finding"
    // 책등으로 책 찾기 (BookNavigationBookFindingView)
    case spineHelp = "spine_help"
    // 책등으로 책 찾기 → 못 찾았어요 (BookNavigationBookHelpView)
}

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
