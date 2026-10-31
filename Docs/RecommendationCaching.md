# 추천 도서 사전 캐싱과 다음 접속 표시 — #71

추천 결과의 목록과 표지를 한 묶음으로 저장하고, 다음 접속에서 네트워크를 기다리지 않고 복원한다. 현재 화면의 추천 A와 다음 접속용 추천 B를 구분한다. 구현·오프라인 검증과 실제 기기 성능 검증은 구분한다.

## 사용자 흐름

1. 앱 시작 시 저장된 추천과 표지를 복원한다. 추천 탭에 들어오기 전에도 앱 루트에서 시작한다.
2. 저장본 A가 있으면 먼저 표시하고 다음 추천 B를 준비한다. 준비가 끝나도 현재 화면 A는 유지한다.
3. 추천 결과에서 이미 저장한 정상 표지는 재사용하고, 없는 표지만 최대 두 개씩 받는다.
4. B에 필요한 표지를 모두 검증한 뒤 목록 파일을 atomic 교체한다. 다음 접속에서는 B를 복원한다.
5. 최초 접속에는 준비 중 안내를 표시한다. 첫 정상 묶음이 완성되면 바로 표시한다.
6. 빈 결과·전송/서버 오류·손상 이미지가 있으면 이전 정상 목록을 보존하고 재시도를 제공한다. 이미지 미제공이 확인된 책은 기본 표지와 함께 정상 목록에 포함한다.

여기서 **접속**은 앱 프로세스의 첫 시작과 `background → active` 복귀다. 탭 이동이나 `inactive → active` 전환만으로는 다시 준비하지 않는다. 명시적 재시도는 새 요청으로 처리한다. 앱이 종료되거나 iOS가 실행을 중단해도 다음 추천 준비의 완료를 보장하는 구조는 아니다.

## 1. 디스크 저장

`Clients/Book/Cache/RecommendationCacheStore.swift`

- Foundation actor가 목록·표지 파일의 읽기와 쓰기를 직렬화한다.
- `Application Support/RecommendationCache-v2/recommendations.json`에 마지막 정상 목록을 기록한다.
- `covers/<SHA256(원본 표지 URL)>.image`에 이미지 파일을 저장한다. URL 문자열을 파일 이름으로 직접 사용하지 않는다.
- 재생성 가능한 지원 데이터이므로 디렉터리에 `isExcludedFromBackup = true`를 설정한다.
- `StoredBook`과 `Manifest`는 Client 내부의 Codable 저장 형식이다. 팀이 공유하는 `Book`에 필드나 Codable 요구를 추가하지 않았다.
- `CachedRecommendations.books`에는 원격 표지 주소를 보존한다. `displayBooks`는 표시할 때만 `imageURL`을 로컬 파일 주소로 바꾼다.

```swift
// 모든 표지 데이터 검증과 파일 쓰기가 먼저 끝난 상태
let data = try JSONEncoder().encode(manifest)
try data.write(to: manifestURL, options: .atomic)
```

표지 URL이 원래 없는 책과 원격 이미지 미제공이 확인된 책은 기본 표지로 표시할 수 있는 정상 항목이다. 그 외 다운로드·변환 실패가 있으면 새 묶음을 활성화하지 않는다. 누락된 파일을 미제공으로 추정하지 않으며, 복원 시 목록 버전·중복 ID·표지 파일 이름·이미지 내용을 확인한다.

2026-10-31 큰 표지 우선 요청 정책에 맞춰 live 저장 폴더를 `RecommendationCache-v2`로 전환했다. 이전 저해상도 표지 묶음은 복원하지 않고 첫 실행에서 추천과 표지를 다시 준비한다. 이전 폴더는 자동 삭제하지 않으며 manifest 형식은 v2를 유지한다.

2026-10-27 표지 오류 보완에서 manifest v2에 선택적인 `coverUnavailable` 표식을 추가했다. v1 저장본도 읽는다. 미제공은 원격 URL과 표식을 보존하되 이미지 파일을 요구하지 않고 표시용 imageURL만 nil로 만든다. 다음 추천 준비에서는 해당 원격 URL을 다시 확인하므로 나중에 표지가 생기면 정상 파일로 회복할 수 있다. 전송 실패·5xx·손상 이미지는 이 표식으로 저장하지 않는다.

저장 성공 후 현재 표시 중인 목록, 열린 상세 화면, 다음 접속용 목록이 참조하지 않는 표지를 정리한다. 이전 접속의 늦은 준비 작업은 preparation ID 검사로 저장을 거부한다.

## 2. 접속 시 복원

`Clients/Book/Cache/RecommendationCacheClient.swift`, `Features/Home/HomeFeature.swift`

- 기존 TCA DependencyKey 방식으로 `restore`, `prepare`, `retainDisplayedCovers`를 주입한다.
- 복원한 로컬 목록을 먼저 액션으로 반영하고, 그 뒤 추천 알고리즘과 표지 준비를 수행한다.
- 각 접속의 UUID를 액션에 연결한다. 이전 접속에서 늦게 온 성공·실패·복원 결과는 무시한다.
- HomeView의 task가 끝나거나 탭을 떠났다는 이유만으로 다음 접속 준비를 취소하지 않는다. 새 접속이 시작되면 이전 작업을 취소한다.

```swift
let cached = try? await recommendationCacheClient.restore()
await send(.recommendationsRestored(sessionID, cached))
let books = try await bookRecommendationClient.fetch(6)
let prepared = try await recommendationCacheClient.prepare(books)
await send(.recommendationsLoaded(sessionID, prepared))
```

실제 코드는 각 비동기 경계에서 취소를 확인하고, 빈 추천을 거르며, 현재 화면·상세 화면의 표지도 보존한다.

`Shared/BookCover/SharedImageLoader.swift`, `BookCoverPipeline.swift`, `BookCoverView.swift`

- 이전 작업에서 작성되어 있던 공통 표지 로더·모델·뷰를 재사용했다. URL별 NSCache·진행 중 요청 공유·구독자별 취소·250ms 유예를 그대로 유지했다.
- 선택적인 `readLocalImage`를 추가해 로컬 표지를 첫 표시 상태를 만들 때 읽고 메모리에 보관한다. 정상 파일이 있으면 네트워크용 로딩 표시를 거치지 않는다.
- Pipeline은 파일 URL도 읽는다. HomeView와 BookDetailView의 독립 AsyncImage를 공통 BookCoverView 호출로 교체했다.
- 후속 통합에서 기존 검색 결과 캐시·검색 화면과 추천 표지 사전 로딩을 같은 브랜치에 연결했다. 원래 프로젝트 폴더가 현재 작업 기준이다.

## 3. 다음 추천 준비

`Clients/Book/Cache/RecommendationCachePreparer.swift`

- `BookRecommendationClient.fetch(6)`가 첫 추천·맞춤 추천 결과를 기존 `Book`으로 변환해 전달하고, 준비기는 그 결과의 목록·표지만 저장한다.
- 같은 표지 URL은 중복 제거한다. 정상 로컬 파일이 있으면 다시 다운로드하지 않는다.
- 없는 표지는 throwing task group으로 최대 두 개씩 준비한다. 미제공으로 분류한 표지만 별도로 표시하고, 나머지 수신 실패나 취소가 있으면 목록 저장으로 넘어가지 않는다.
- live 다운로드는 기존 BookCoverPipeline을 사용하므로 화면에서 완료했거나 받고 있는 이미지 요청도 공유한다. 검증 가능한 이미지 데이터로 변환해 저장한다.
- 수신 도중 더 새로운 작업이 시작되면 이전 작업은 저장 단계에서 거부한다.

```swift
if let data = try await store.coverData(for: url) {
    covers[url] = data
} else {
    missing.append(url)
}
```

`App/AppFeature.swift`, `App/AppView.swift`

- 앱 루트의 시작 액션과 scenePhase 변화를 연결했다. 위치 스트림의 기존 수명·전달 액션은 유지했다.
- 같은 루트 시작의 중복 호출, 단순 inactive 복귀, 추천 탭 재진입은 추가 준비를 시작하지 않는다.

## 4. 예외 처리와 표시

`Features/Home/HomeView.swift`

| 상황 | 표시와 보존 |
| --- | --- |
| 최초 접속·캐시 없음 | ‘추천 도서를 준비하고 있어요’ 표시 후 첫 정상 묶음 표시 |
| 정상 저장본 있음 | 로컬 목록·표지를 먼저 표시하고 다음 추천 준비 |
| 추천 조회·표지 준비 실패 | 오류와 다시 시도 버튼. 이전 추천이 있으면 계속 표시 |
| 빈 정상 표지 응답·204·404·410 | 미제공 표지를 기본 아이콘으로 표시하며 목록은 저장. 다음 준비에서 다시 조회 |
| 빈 추천 응답 | 재시도 가능한 오류. 정상 저장본을 빈 목록으로 교체하지 않음 |
| 저장본 손상·파일 유실 | 캐시 없는 조회 경로로 복구. 다시 실패하면 오류 안내 |
| 갱신 중 종료·취소 | 이전 정상 목록 유지. 준비 완료 전 목록을 교체하지 않음 |
| 상세 화면을 연 채 다음 접속 | 해당 상세 표지 파일을 정리 대상에서 제외 |

## 추가·수정·삭제 요약

| 구분 | 파일과 목적 |
| --- | --- |
| 새 구현 | RecommendationCacheStore: 목록·표지 영속화, 검증, atomic 교체와 파일 보존 |
| 새 구현 | RecommendationCachePreparer: 변경 표지 준비, 중복·동시 작업 제한, 이전 작업 저장 차단 |
| 새 구현 | RecommendationCacheClient: 기존 TCA DI에 복원·준비·파일 보존 기능 연결 |
| 기존 코드 재사용 후 확장 | SharedImageLoader, BookCoverPipeline, BookCoverView와 기존 로더 테스트: 로컬 파일 즉시 표시 지원 |
| 수정 | HomeFeature: 직접 추천 조회를 복원 → 다음 추천 준비 흐름으로 변경. 접속 ID·로딩/준비·오류·저장 시각 상태 추가 |
| 수정 | HomeView, BookDetailView: 표지 뷰 공통화. 추천의 최초 로딩·오류·재시도 화면 추가 |
| 수정 | AppFeature, AppView: 앱 시작·background 복귀의 접속 수명 연결 |
| 추가 | 저장소·준비·Home·앱 접속 테스트와 Scripts/validate_recommendation_cache.py |
| 제거한 코드 | HomeView와 BookDetailView의 독립 AsyncImage 처리. 캐시 없이 추천 결과를 바로 화면 배열에 덮어쓰던 경로 |

전체 파일을 삭제하지 않았다. Book 도메인 계약·API 인증 코드·다른 지도 동작은 유지했다. 검색 결과 캐시는 후속 통합에서 기존 구현을 반영했다.

## 검증과 실행 방법

```sh
python3 Scripts/validate_recommendation_cache.py
```

- 실제 API·키·설정 파일 없이 macOS SwiftPM의 별도 소스 사본에서 핵심 **20개 테스트**를 실행했다. 저장소 7개, 표지 준비 5개, 공통 이미지 로더 8개다. 로더 8개 중 7개는 기존 테스트를 재사용했다.
- 앱 전체 Swift 소스의 iOS 모듈 생성과 BookDetailTests 전체 소스 타입 검사를 통과했다. 기존 로컬 TCA 의존성 모듈과 매크로를 사용했으며, 앱은 실제 프로젝트의 Swift 5 언어 모드·MainActor 기본 격리, 테스트는 Swift 6 언어 모드에 맞췄다.
- Home 추천 7개와 App 접속 1개 TCA 테스트는 타입 검사만 했다. 실제 iOS test runner에서 실행한 결과는 아니다.
- 전체 `xcodebuild build-for-testing`은 package manifest의 sandbox 실행 오류로 완료하지 못했다. CoreSimulator 서비스 연결도 실패했다. 앱 소스 모듈 생성과 전체 빌드 성공을 동일하게 취급하지 않는다.
- UIKit 실제 화면·실기기 접속 왕복·변경 후 첫 표시 시간·메모리·실서비스 응답은 측정하지 않았다. 기존 IndoorRouteClient의 Sendable 경고도 이번 범위에서 수정하지 않았다.

후속 통합에서는 검색 결과 캐시 4개를 더해 **총 24개 테스트**가 통과했다. 현재 소스가 검증한 통합 사본과 같음을 확인했으며, 커밋만 생성하는 과정에서는 테스트를 다시 실행하지 않았다.

표지 오류 보완 후에는 `Scripts/validate_recommendation_cache.py`가 표지 모델·실패 분류·검색 캐시 테스트도 포함한다. 오프라인 **39개 테스트 / 6개 suite**, 앱 전체 iOS 모듈 생성과 BookDetailTests 전체 Swift 6 타입 검사를 통과했다. 실제 표지 공급처·실기기 화면에서의 검증 결과와 구분한다.

2026-10-28 추천 연결에서는 첫 추천·맞춤 추천·홈 모델 변환 **26개 테스트 / 3개 suite**를 별도 macOS 검증 사본에서 실행했다. 실제 DependencyValues 구현을 사용하고 ComposableArchitecture 모듈 이름은 Dependencies·ConcurrencyExtras를 다시 내보내는 얇은 모듈로 대체했다. 실제 인증 설정은 복사하지 않고 API 키가 nil인 가짜 설정을 사용했다. 앱 전체 iOS 모듈 생성과 BookDetailTests 전체 Swift 6 타입 검사도 통과했다. 새 Home 캐시 통합 테스트는 캐시 유무 두 경우를 포함하며 타입 검사까지만 수행했다. iOS TCA runner·실서비스 호출·실기기 화면 검증은 별도로 남아 있다.

## 남은 통합 확인

- 2026-10-28 통합: `BookRecommendationClient.liveValue`에서 찜·최근 검색이 없으면 `ColdStartRecommendationClient`, 있으면 `PersonalizedRecommendationClient`를 호출한다. 맞춤 추천의 오류·빈 결과는 첫 추천으로 대체하고, 취소는 그대로 전달한다. 관심사는 기존 알고리즘의 `placeholderInterests`를 사용하며 온보딩 저장값 연결은 남아 있다.
- 추천의 `recordID`에서 숫자 레코드 번호를 추출해 기존 `BookClient.search`로 최대 6권의 메타데이터를 한 번에 보완한다. 검색 응답 순서와 관계없이 추천 순서·검증된 표지 URL을 유지한다. 조회되지 않은 레코드는 제외하며 결과가 전부 비면 HomeFeature의 기존 오류·캐시 보존 경로를 따른다.
- `HomeFeature`의 복원 → `fetch(6)` → 표지 준비·저장 경로와 `HomeView.recommendedBooks`를 그대로 재사용한다. 별도의 첫 추천·맞춤 추천 배열에만 결과가 쌓이던 경로를 제거했으므로 앱 시작·백그라운드 복귀·재시도가 같은 알고리즘을 거친다.
- 표지 변경 판별은 현재 원격 URL 기준이다. 같은 URL의 이미지 내용이 바뀌는 공급처라면 URL에 버전을 반영하거나 별도 재검증 정책을 추천 계약에 추가해야 한다.
- 현재 앱에 계정/추천 입력별 캐시 키가 없다. 해당 입력이 추가되면 캐시 namespace와 무효화 조건을 함께 추가해야 한다.
- 첫 접속의 네트워크 응답 시간은 이 캐시로 제거되지 않는다. 이번 구현은 최초 로딩 안내와 정상 데이터의 다음 접속 복원을 제공한다.
- 실기기에서는 A 복원 → B 준비 중 탭 왕복 → 앱 background/복귀 → B 표시, 오프라인·파일 유실·중간 종료를 확인한다.
- 실제 추천의 홈·캐시 연결은 2026-10-28에 추가했다. 실서비스 응답·실기기 성능 검증은 별도로 확인한다. 이 문서 갱신만으로 이슈를 자동 종료하지 않는다.
