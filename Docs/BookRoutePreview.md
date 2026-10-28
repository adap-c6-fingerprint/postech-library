# 책 입력을 받는 경로 미리보기 — PLI-96 / #116

사용자 요청에 따라 `feat/#116-pli-96-route-preview`에서 기본 화면을 준비한다. PLI-54 / #74용 별도 브랜치는 만들지 않는다. 책 입력을 받는 뼈대에 한 권 기준 다크 레이아웃을 추가한 디자인 단계다. PLI-96의 최종 디자인 인수나 실제 경로 기능 완료를 의미하지 않는다.

## 책 식별자와 전달 흐름

- `BookClient.search`는 Primo `pnx.control.recordid.first`를 읽고 `primo:<recordID>`를 `Book.id`와 `Book.controlNumber`에 보존한다. ISBN은 별도 필드다.
- `Book.recordKey`는 찜·바구니 중복 판정용이며, controlNumber가 있으면 이를 쓰고 없으면 서지정보 조합을 사용한다. `recordKey`나 ISBN을 원본 Primo recordID로 간주하지 않는다.
- 검색의 `bookSelected`는 받은 Book을 `BookDetailFeature.State.book`에 넣는다. 추천도 BookRecommendationClient에서 BookClient의 메타데이터와 추천 표지를 합쳐 같은 Book으로 상세에 전달한다.
- 상세의 미리보기는 `[store.book]`을 전달한다. 바구니는 선택 ID가 현재 목록에 존재하는 책만 원래 목록 순서로 전달한다. 전체 바구니·선택 집합·원본 Book을 바꾸지 않는다.
- `BookRoutePreviewView(books: [Book])`는 전달받은 책의 값 스냅샷을 입력으로 받는다. 표지·제목·저자를 화면에 보여주며 ID/controlNumber/ISBN 등 기존 Book 정보는 모두 보존한다. 화면 진입 시 BookClient를 다시 호출하지 않는다. 표지는 기존 공통 BookCoverView를 사용한다.
- 검색·추천 외의 Book이 항상 Primo 식별자를 가진다고 가정하지 않는다. 실제 소장 위치 해석을 연결할 때 출처·식별자 유효성을 확인해야 한다.

## 기존 코드와 재사용 경계

- `Features/IndoorMap/IndoorRouteSettingsView`는 `IndoorMapFeature`의 `ShelfDestination`과 계산된 경로를 표시하는 기존 단일 서가 화면이다. 책 배열을 받는 화면으로 바꾸지 않는다.
- 추후 실제 지도는 `IndoorMapView` / `IndoorMapKitView`, 경로 계산은 `IndoorRouteClient` / `IndoorRouteSearchEngine`, 상태·취소·오류 처리는 기존 `IndoorMapFeature`를 참고하거나 재사용할 수 있다.
- 현재 Book에는 청구기호·Fixture·도착 노드가 없다. 책 → 소장 위치/청구기호 → 실제 서가 → 도착 노드 연결은 별도 단계이며, 다른 담당자의 PR #153/#75와 범위를 맞춰야 한다.
- 이 기본 화면은 지도·소장 위치 요청·경로 계산·방문 순서 최적화·그룹 기반 좌우회전·안내 시작을 실행하지 않는다. 바구니 선택 상한 등 별도 기능 규칙도 추가하지 않는다.

## 확인 방법

1. 검색 결과나 추천에서 책 상세를 열고 `길찾기 경로 미리보기`를 누른다. 해당 책 한 권의 제목·저자가 표시되고 뒤로가면 원래 상세로 복귀한다.
2. 책바구니에서 일부 책을 선택하고 하단 미리보기를 누른다. 선택한 책만 바구니 순서대로 표시된다. 뒤로가면 바구니 목록과 선택은 유지된다.
3. 선택이 없으면 바구니의 미리보기 버튼은 비활성화된다. 빈 배열을 직접 전달한 경우에는 빈 상태를 표시한다.
4. 같은 제목의 다른 Primo recordID를 가진 책도 Book.id로 각각 구분한다. 현재 단계에서 책 ID를 지도 UUID나 노드 ID로 바꾸지 않는다.

## 한 권 기준 디자인

- 상단 도면 영역과 하단의 둥근 다크 패널을 사용한다. 하단에는 뒤로가기, 도보 시간·단계·거리와 출발 버튼, 내 위치→책 경로 요약, 도서 및 청구기호 카드를 배치한다.
- Button·Label·ScrollView·SF Symbols 등 SwiftUI 기본 컴포넌트와 기존 BookCoverView를 재사용한다. 하단 콘텐츠는 큰 글씨·작은 화면에서도 스크롤할 수 있다.
- 도면은 Canvas로 그린 디자인용 예시이며 `지도 예시`라고 표시한다. 실제 IMDF·위치·경로를 요청하지 않는다. 시간·단계·거리는 `—`이며 출발 버튼은 비활성화한다.
- 제목·저자·표지는 전달받은 Book을 사용한다. 아직 없는 소장 위치·청구기호·대출 상태는 확인 전으로 표시한다.
- 입력 배열은 유지한다. 여러 책이 전달돼도 누락시키지 않고 카드 목록에 표시하되, 다중 목적지 경로 계산이나 방문 순서는 구현하지 않는다.

## 이번 단계 검증

- 다크 레이아웃은 원본 Book·BookText·공통 BookCover 구현·BookRoutePreviewView를 별도 iOS 검증 앱으로 함께 컴파일하고 iPhone 17 Pro / iOS 26.5 시뮬레이터에서 렌더링했다. 샘플 Book만 전달했으며 실제 API·위치 요청은 실행하지 않았다.
- 기본 글씨 화면에서 버튼 줄바꿈과 상태바 겹침을 보정했다. 접근성 글씨 크기에서는 출발 버튼을 아래 줄로 내려 시간·단계·거리 영역의 폭을 확보한다.
- 실제 iOS Simulator SDK에서 원본 Book·BookText와 BookRoutePreviewView·BookBasketView의 타입 검사를 통과했다(Swift 5 / MainActor 기본 격리).
- BookDetailView 문법 검사, Xcode 프로젝트 plist 검사, git diff --check를 통과했다.
- 비밀 설정을 제외한 임시 사본의 전체 앱 빌드는 기존 잠금 파일의 xctest-dynamic-overlay 항목 누락으로 먼저 중단됐다. 임시 사본에서 의존성을 해석한 뒤에는 기존 TCA 등 패키지 매크로 활성화 확인에서 중단됐다. 원본 Package.resolved나 매크로 신뢰 설정은 변경하지 않았다.
- 전체 앱 빌드 성공·실제 화면 push/pop·바구니 선택 유지의 조작 검증을 완료한 것으로 취급하지 않는다. 위 확인 방법에 따른 GUI 검수는 남아 있다.
