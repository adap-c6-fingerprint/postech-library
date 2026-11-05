# PLI-267 — 동의 기반 Analytics / Crashlytics

## 범위

공용 Firebase 프로젝트 `pobook-6bbc4`를 사용한다. 별도 서버·위치 전송·전체 선호도 원장은 이번 작업에서 제외한다.
기존 Book / UserProfile / BookNavigationSession 계약과 검색·추천·길안내 계산은 유지하며, 성공·실패·취소 지점에서 AnalyticsClient로 코드만 전달한다.
이벤트 선언과 실제 호출 위치는 아래 표에 한정된다. 기존 HTML의 70개 이벤트 전체 구현을 뜻하지 않는다.

## 동의와 데이터 경계

- 최초 실행에 선택 화면을 표시한다. 사용 분석 / 오류 진단은 서로 독립적이며 처음에는 모두 꺼져 있다.
- 모두 거부해도 기존 기능을 사용할 수 있다. 마이페이지 → 데이터 수집 설정에서 변경한다.
- 앱은 분석에 동의한 활성 화면에서만 직접 행동 이벤트를 기록한다. 동의 전 행동을 나중에 소급 전송하지 않는다.
- Analytics 철회: 수집 중단, 사용자 ID 해제, Analytics 로컬 데이터 초기화, 진행 중 요청·로컬 프로필 연결 초기화. 이미 서버에 전송된 데이터의 삭제 요청 기능은 포함하지 않는다.
- 임의의 설치별 UUID를 Analytics user_id로 사용한다. 학번·이메일·광고 ID는 넣지 않는다. 철회 후 다시 동의하면 새 UUID다.
- 검색어 원문, 제목·저자, 청구기호, 관심 분야 전체 목록, 좌표·층·서가 번호, 오류 원문은 이벤트 필드로 보내지 않는다. 도서는 검증된 `alma + ASCII 숫자` recordID만 사용하고 나머지는 unknown으로 바꾼다.
- SDK 자체의 자동 세션·기기·앱 정보는 별도다. 앱의 좌표 전송이 없다는 말이 GA의 IP 기반 국가/지역 추정까지 없다는 뜻은 아니다. 보관 기간·접근 권한·개인정보 안내는 배포 담당자가 콘솔 및 정책에서 확정해야 한다.

## 학과·선호도 연결

`@Shared(.userProfile)` 최초 로드 / 온보딩 완료 / 마이페이지 변경
→ 루트의 updateProfile
→ 번들 RecommendationDataset의 selectionKey를 안정적인 affiliation ID로 변환
→ GA 사용자 속성:

| 속성 | 값 | 분석할 때 |
| --- | --- | --- |
| affiliation_id | 예: affiliation-0001 또는 unknown | 학과/소속별 필터. 실제 대응은 JSON의 id/selectionKey 참조 |
| interest_count | 선택한 관심 분야 개수 | 관심사를 몇 개 고른 사용자끼리 비교 |

전체 관심사 이름이나 변경 이력을 서버에 저장하지 않는다. 변경 감지용 해시는 기기에만 저장한다.
profile_version_id는 임의 UUID이며 이벤트를 같은 프로필 버전으로 연결할 때 쓰지만, 전체 선호도 원장이 없으므로 관심사별 과거 분석은 아직 불가능하다.
비동기 학과 조회 도중 동의나 프로필이 바뀌면 이전 결과를 버린다.

## 직접 구현한 이벤트

| 위치 | 이벤트 | 의미 / 연결 |
| --- | --- | --- |
| AppView / 화면 modifier | screen_view, app_visit_started, app_active_interval, screen_active_interval | 화면 코드, 방문 ID, 앱이 활성 상태였던 시간. 60초마다 및 화면/앱 전환 시 겹치지 않는 구간으로 기록 |
| OnboardingFeature | onboarding_started, onboarding_completed | 시작 버튼 / 유효한 프로필 저장 완료. 관심 분야 편집을 최초 온보딩 완료로 세지 않음 |
| AnalyticsRuntime | profile_updated | 프로필 버전 연결. 동의 이전 변경 이력을 복원하지 않음 |
| BookSearchFeature | search_submitted / completed / failed / cancelled | operation_id로 연결, duration_ms 측정. 캐시 응답도 완료이며 cache_hit=yes. 취소 후 늦은 응답은 집계하지 않음 |
| BookSearchFeature | search_result_selected | source=results 또는 recent. 검색어 없이 도서 ID만 |
| BookDetailView | book_detail_viewed | 상세 내용이 나타날 때. 재표시도 포함하는 노출 이벤트이며 고유 방문자 수와 다름 |
| 상세·검색·찜 Feature | book_favorite_changed | 실제 저장 변경 후 added/removed. 여러 권 일괄 제거는 book_count |
| 상세·검색·찜 Feature | basket_book_added, basket_limit_blocked | 신규 담기만 성공. 이미 담긴 책을 다시 눌러도 성공을 더하지 않음 |
| 장바구니·검색 Feature | basket_books_removed | 실제 제거 권수 |
| HomeFeature | recommendation_load_completed / failed, recommendation_selected | kind=restored / prepared_for_next_visit. 다음 접속용 준비 완료를 현재 화면 카드 노출로 오해하면 안 됨 |
| BookRoutePreviewFeature | guidance_requested, route_calculation_started / completed / failed / cancelled | 유효한 계산 요청부터 측정. 완료 시 navigation_id로 실제 안내와 연결 |
| BookNavigationFeature | navigation_started / completed / cancelled | 실제 안내 수명 기준. 앱 활성 복귀는 새 시작이 아님. 화면 사라짐은 일시 정지이며 취소로 꾸미지 않음 |
| BookNavigationFeature | navigation_step_changed | 경유지 내 RouteGuidanceProgress.stepIndex 변경. 원시 edge-step 인덱스이며 미리보기의 그룹 단계 수와 같은 값이 아님 |
| BookNavigationFeature | navigation_quality_changed | on_route / unknown_floor / ambiguous_position / off_route / unusable_position. 연속 같은 상태는 한 번만 |
| BookNavigationFeature | destination_arrival_detected | 자동 도착 근접 판정 1회/경유지. 테스트 도착 버튼은 이 이벤트를 만들지 않음. 책을 실제로 찾았다는 확인과는 다름 |

공통 연결 키: event_id / launch_id / visit_id / profile_version_id / build_environment.
검색과 경로 요청은 operation_id, 실제 안내는 기존 session.id를 navigation_id로 사용한다.
이벤트별 book_count / step_count / distance_m는 계산 결과의 요약이며 위치 스트림은 아니다.
노출률/클릭률을 위한 카드 50%·1초 가시성 측정, 모든 재탐색·권한·네트워크 예외의 개별 이벤트는 후속 범위다.
사용 시간은 앱 루트가 살아 있고 scenePhase=active인 구간만 합한다. 강제 종료 직전 미전송 구간은 누락될 수 있다.

## 테스트 트래픽

- build_environment: simulator / development / testflight / production / unknown.
- Simulator는 항상 simulator, Debug 실기기는 development. Release는 검증된 AppTransaction 환경으로 구분하며 확인 실패 시 unknown이다.
- 같은 Firebase 프로젝트이므로 콘솔과 BigQuery에 테스트 데이터도 들어간다. 운영 분석은 production만 필터링한다. Release 환경 판별이 끝나기 전에는 앱이 직접 기록하는 app_visit_started·screen_view 등의 이벤트도 unknown으로 남을 수 있어 이 필터에서 제외된다. 자동 SDK 이벤트는 앱의 공통 필드가 없을 수도 있다. 초기 이벤트를 보류하거나 소급 수정하지 않는다.
- 테스트모드 버튼과 simulation/replay 안내에 is_test=yes를 붙인다. 실제 사용자 행동만 볼 때 is_test=yes를 제외한다.
- GA의 기본 session과 앱의 visit_id는 별도다. 앱 visit는 30분 이상 비활성 뒤 새로 생성한다.
- UUID 식별자를 GA 맞춤 측정기준으로 등록하면 값이 너무 다양해진다. ID 연결은 BigQuery에서 하고, GA에서는 낮은 다양성의 코드와 개수 중심으로 본다.

## 오류 진단과 symbols

Crashlytics 자동 보고는 계속 false다. 진단 SDK가 기기에 로컬 기록을 만드는 것 자체를 막는 설정은 아니다.
진단 동의를 처음 허용하거나 실행 중 철회하면, Firebase가 구성된 실행에서는 그 시점까지 쌓인 미전송 보고서를 즉시 폐기한다.
동의를 바꾼 뒤 같은 실행에서 기록된 보고서는 다음 실행 시작 시 폐기한다. Firebase가 구성되지 않은 실행에서도 철회 기록은 저장하며 다음 정상 실행에서 이전 보고서를 폐기한다.
실행 시작부터 종료까지 진단 동의가 유지된 실행의 보고서만 다음 실행에서 전송한다.
이미 시작된 업로드나 서버에 도착한 보고서를 철회로 회수할 수는 없다.
breadcrumb는 행동 코드만 기록한다. 사용자 지정 키는 screen_code, last_action_code, navigation_id, visit_id, launch_id, build_environment다.
진단 동의 철회 시 screen_code, last_action_code, navigation_id, visit_id, launch_id를 초기화하며 build_environment는 유지한다. 전체 reducer action/state/error 원문을 덤프하지 않는다.

Debug 설정 화면에는 사용자가 확인한 뒤 누르는 비치명 오류 테스트 버튼이 있다. 첫 진단 동의 후 한 번 재실행하고 사용한다.
진짜 크래시 테스트는 자동 실행하지 않았다.

Archive에만 마지막 Crashlytics symbols 업로드 단계를 실행한다. upload-symbols --build-phase를 전경에서 실행해 실패가 빌드 로그와 종료 코드에 드러나도록 한다. 실행 파일은 샌드박스 입력 경로에도 선언한다. Release dSYM 설정은 기존 설정을 유지한다.
표준 Xcode SourcePackages 경로를 사용한다. 별도 -clonedSourcePackagesDirPath를 쓰는 CI는 해당 단계의 SDK 경로도 그 환경에 맞춰야 한다.
Archive에는 로컬/CI가 제공하는 GoogleService-Info.plist가 필요하다. 파일은 계속 Git에서 제외하며 일반 Debug 빌드에는 symbols 업로드를 실행하지 않는다.

## 콘솔 / 실기기 검증 체크리스트

1. 설정 plist를 앱 루트에 별도 배치하고 팀 Xcode에서 기존 TCA 등 매크로 사용을 승인한 뒤 빌드한다.
2. 새 설치 → 모두 거부: 직접 이벤트 없음. 진단 보고서 없음. 검색/지도/안내 정상.
3. 분석만 허용 → 재실행: GA DebugView에서 screen_view, 검색 시작/종료, 상세/찜/장바구니를 확인한다. 진단 자동 전송은 여전히 꺼짐.
4. Xcode Scheme 실행 인자 -FIRDebugEnabled는 개발 검증에만 사용한다. 검증 후 제거한다.
5. 온보딩/학과 변경 뒤 affiliation_id와 interest_count를 확인한다. 원문 관심사·검색어·좌표가 없는지 확인한다.
6. 검색 중 입력 변경 / 새 요청 / 늦은 응답에서 operation_id별 종료가 최대 한 번인지 확인한다.
7. 안내 시작 → 일시 정지/복귀 → 종료에서 시작 중복이 없는지, 테스트모드가 is_test=yes인지 확인한다.
8. 분석 철회 → 이후 직접 이벤트 없음 → 재동의 → user_id 새 값. 철회 중 시작된 요청의 종료를 소급 집계하지 않음.
9. 진단 동의 저장 → 앱 재실행 → 비치명 오류 테스트 → 앱 재실행 → Crashlytics 수신 확인. 진단 철회 후 보고서 미전송 확인.
10. 실제 Release Archive의 symbols 업로드와 스택 복원을 확인한다. 실제 테스트 크래시·TestFlight·App Store 환경 분리는 별도로 확인한다.
11. GA 관리 → 맞춤 정의에서 사용자 범위 affiliation_id / interest_count, 이벤트 범위 build_environment / is_test / kind / source / quality_state 등을 필요한 것만 등록한다. 등록 이후 수집부터 보고서에 반영되므로 일찍 설정한다.
12. 보관 기간, 내부 트래픽 필터, 접근 권한, App Store 개인정보 공개와 수집 안내 문구는 배포 전에 담당자가 검토한다.

## 개발 검증

```sh
bash Scripts/verify-analytics.sh
python3 -m unittest discover -s Scripts/tests -v
plutil -lint fingerprint-library/Info.plist fingerprint-library.xcodeproj/project.pbxproj
```

순수 Swift 검사는 동의 조합·진단 보고 자격·요청 지연/취소·메모리 상한·도서 ID 검사를 실제 실행한다.
AnalyticsFeatureTests는 TCA에서 캐시 검색·늦은 응답·중복 장바구니 성공 집계를 검사한다.
정적 검사는 SDK 연결과 동의 경계/Archive 연결을 확인하며 실기기 수신을 대신하지 않는다.

### 2026-11-05 확인 결과

- Scripts/tests 34개 통과. 순수 Swift의 동의·요청 검사는 별도 실행도 통과했다.
- 변경 Swift 전체 구문 검사, plist/project 문법 검사 통과.
- 실제 Firebase 13.1.1 헤더로 AnalyticsRuntime / 새 설정 화면 / 화면 modifier를 Simulator Debug 및 실기기 Release 대상에서 독립 타입 검사했다. Firebase 헤더용 임시 module map을 사용한 검사이며 앱 링크를 검증한 것은 아니다.
- 전체 앱 빌드는 기존 ComposableArchitectureMacros / CasePathsMacros / DependenciesMacrosPlugin / PerceptionMacros / SwiftNavigationMacros 실행 승인 요구로 의존성 그래프 단계에서 중단됐다. 승인을 우회하지 않았다. AnalyticsFeatureTests와 기존 iOS 테스트도 실행 완료로 취급하지 않는다.
- 실제 Firebase/GA 수신, Release Archive symbols 업로드, TestFlight/운영 환경 판별과 화면 회귀는 미확인이다.
- 팀 규칙상 개인정보 수집과 여러 기능에 걸친 L 영향도다. 셀프 검토만으로 배포 승인하지 않으며, 결과는 needs_human_review: 위 실기기 검증과 사람의 개인정보 안내·코드 검토가 필요하다. PR·merge는 진행하지 않았다.
