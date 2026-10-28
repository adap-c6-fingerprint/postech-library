# 책 입력을 받는 경로 미리보기 — PLI-96 / #116

사용자 요청에 따라 `feat/#116-pli-96-route-preview`에서 작업한다. PLI-54 / #74용 별도 브랜치는 만들지 않는다. `dev`의 `77bfa4c`(#153 서가 연결)를 병합했다. 현재 범위는 한 권 기준 다크 미리보기와 **실제 IMDF 위의 고정 목데이터 목적지 서가 강조**다. 경로 계산·턴바이턴·안내 시작 완료를 의미하지 않는다.

## 책 식별자와 전달 흐름

- `BookClient.search`는 Primo `pnx.control.recordid.first`를 읽고 `primo:<recordID>`를 `Book.id`와 `Book.controlNumber`에 보존한다. ISBN은 별도 필드다.
- `Book.recordKey`는 찜·바구니 중복 판정용이며, controlNumber가 있으면 이를 쓰고 없으면 서지정보 조합을 사용한다. `recordKey`나 ISBN을 원본 Primo recordID로 간주하지 않는다.
- 검색의 `bookSelected`는 받은 Book을 `BookDetailFeature.State.book`에 넣는다. 추천도 BookRecommendationClient에서 BookClient의 메타데이터와 추천 표지를 합쳐 같은 Book으로 상세에 전달한다.
- 상세의 미리보기는 `[store.book]`을 전달한다. 바구니는 선택 ID가 현재 목록에 존재하는 책만 원래 목록 순서로 전달한다. 전체 바구니·선택 집합·원본 Book을 바꾸지 않는다.
- `BookRoutePreviewView(books: [Book])`의 진입 계약은 유지하지만, 이번 사용자 요청에 따라 **이 화면 안에서만 입력 책을 무시하고 동물농장 한 권을 고정 목적지로 사용한다**. 상세·바구니의 원본 Book이나 선택 상태는 바꾸지 않는다. 화면에 고정 목데이터 테스트임을 표시한다. 실제 선택 도서 연결 단계에서 이 임시 처리를 해제해야 한다.
- 검색·추천 외의 Book이 항상 Primo 식별자를 가진다고 가정하지 않는다. 실제 소장 위치 해석을 연결할 때 출처·식별자 유효성을 확인해야 한다.

## 기존 코드와 재사용 경계

- `Features/IndoorMap/IndoorRouteSettingsView`는 `IndoorMapFeature`의 `ShelfDestination`과 계산된 경로를 표시하는 기존 단일 서가 화면이다. 책 배열을 받는 화면으로 바꾸지 않는다.
- 추후 실제 지도는 `IndoorMapView` / `IndoorMapKitView`, 경로 계산은 `IndoorRouteClient` / `IndoorRouteSearchEngine`, 상태·취소·오류 처리는 기존 `IndoorMapFeature`를 참고하거나 재사용할 수 있다.
- Book의 공유 계약은 바꾸지 않는다. 최신 dev의 `BookShelfMapFeature`와 `BookHoldingShelfResolver`가 별도 소장 정보의 청구기호를 실제 fixture에 연결한다. 이 화면은 해당 Feature에 사용자 제공 소장 정보를 미리 넣어 네트워크 조회 없이 같은 매칭 로직을 사용한다.
- 기존 `IndoorMapView`/`IndoorMapKitView`와 서가 강조·카메라 기능을 그대로 사용한다. 가짜 Canvas 도면·점선 경로·위치 마커는 제거했다. 지도와 레이블을 읽은 뒤 목적지 층을 선택하고 서가 도형에 카메라를 맞춘다. 지도 영역 자체를 하단 패널 위로 제한해 목적지뿐 아니라 로딩·실패·재시도 UI도 패널에 가리지 않게 한다.
- 실제 도서의 `길안내 받기`와 이 알파 미리보기는 별도 진입점으로 보존한다. dev의 실제 소장 조회·1~3권 제한·검색/상세/바구니 상태는 변경하지 않는다.
- 경로 계산·방문 순서 최적화·그룹 기반 좌우회전·안내 시작·위치 권한 요청은 하지 않는다. 지도 로딩 실패 시 기존 지도 재시도 UI, 레이블 실패 시 기존 재시도 UI를 사용한다.

## 확인 방법

1. 책 상세 또는 책바구니의 **경로 미리보기**로 진입하면 입력 책과 무관하게 동물농장이 표시된다. **길안내 받기**는 기존 dev의 실제 소장 조회 화면으로 이동한다.
2. 화면 로딩 후 3층 `337-A` 서가 한 면만 주황색으로 강조되고, 카메라가 하단 패널 위로 해당 도형을 맞춘다. 주변 IMDF 도형은 일반 스타일로 유지한다.
3. 미리보기에서 뒤로가면 상세 또는 바구니로 돌아간다. 원본 도서·바구니 선택을 변경하지 않는다.
4. 층을 바꿔도 다른 서가를 임의의 목적지로 강조하지 않는다. 목적지는 3층에만 있다.

## 한 권 기준 디자인

- 상단 도면 영역과 하단의 둥근 다크 패널을 사용한다. 하단에는 뒤로가기, 도보 시간·단계·거리와 출발 버튼, 내 위치→책 경로 요약, 도서 및 청구기호 카드를 배치한다.
- Button·Label·ScrollView·SF Symbols 등 SwiftUI 기본 컴포넌트와 기존 BookCoverView를 재사용한다. 하단 콘텐츠는 큰 글씨·작은 화면에서도 스크롤할 수 있다.
- 지도는 앱에 포함된 실제 도서관 IMDF다. 시간·단계·거리는 `—`이며 출발 버튼은 비활성화한다.
- 도서명·저자·소장 위치·청구기호는 아래 목데이터다. 표지는 기존 BookCoverView의 표지 없음 표시를 쓰며, 실제 확인하지 않은 대출 상태를 만들어내지 않는다.

## 고정 목적지와 실제 서가

- 원본 recordID: `alma991003794555103286`
- Book.id / controlNumber: `primo:alma991003794555103286`
- 도서: 동물농장 / George Orwell · 김승욱
- 소장 위치: 박태준학술정보관 단행본3층 / 청구기호: `PR6029.R8 .O79 2021`
- 기존 일반 서고 매칭에 맞춰 이 목데이터만 `82POSTECH_INST` / `MAIN` / `c3b`로 표현한다. 실제 Primo 응답을 조회해 확인한 값이라는 의미는 아니다.
- 기존 범위 검색 결과는 **한 곳**, `S-3F-564-A` / 현장 번호 **337-A**다. fixture UUID는 `8a71e4fa-9952-42e8-b8ce-513b0b738b1a`, 층 UUID는 `2a287490-7514-4f42-bad5-e6619ec45b79`(IMDF ordinal 2)다. 이 fixture UUID를 앱에서 하드코딩해 고르는 것이 아니라 기존 청구기호 검색 결과를 사용한다.

## 첨부 navigation 자료 임베드

사용자가 2026-10-28 제공한 세 파일을 `fingerprint-library/Resources/IndoorMaps/POSTECHLibrary/`에 원본 바이트 그대로 포함했다. Xcode의 기존 `Resources/IndoorMaps` 폴더 리소스 설정을 유지한다.

| 파일 | SHA-256 |
| --- | --- |
| navigation.json | `70ebce44d755b4573ed13c6afac2e2077252e9609cdbdba2f6e3900cdf3ecc87` |
| routing-graph.geojson | `2fe17357e151c5824261fdf9c98b54415a366d64188c5bffc26d659cb7d1bfcb` |
| navigation-feature-links.json | `4aef9a279aaf3727d3dab29d17e84d5b9f2d8265e60ac809fc76119d29053052` |

첨부 HTML 가이드에 따라 fixture와 node는 서로 다른 ID로 보존한다. 목적지 fixture의 sidecar 매핑은 `68ed0070-4842-4488-b381-3cf387733b51` 노드를 가리키고, 층 UUID도 일치한다. 매핑이 없는 경우 근접 노드를 임의로 추정해서는 안 된다.

**아직 실제 경로 로더에는 연결하지 않는다.** 이번 서가 표시는 IMDF + shelfdata + 기존 청구기호 매칭만 사용한다. 그래프에는 노드 723개·엣지 523개, sidecar에는 feature 154개·대표 노드 88개가 있다. 파일끼리 layout_version·해시와 목적지 UUID 연결은 일치하지만, 그래프/descriptor의 층 번호는 3/4이고 같은 층 UUID의 앱 IMDF ordinal은 2/3이다. 기존 엄격한 RoutingGraphMapper에 그대로 넣으면 거부된다. 후속 경로 작업에서 명시적인 변환 계약 또는 동일 시점의 재내보내기를 결정해야 하며, 이번 변경에서는 원본 IMDF·그래프·기존 로더의 검증을 수정/완화하지 않는다. 그룹도 안내 방향이나 통행 우선순위로 자동 해석하지 않는다.

## 검증

- 이번 변경: 실제 원본 Swift IMDF 로더·308개 서가 인덱스 로더·소장 정보 resolver·목데이터를 별도 실행 파일로 컴파일하고 실행했다. 단일 337-A fixture 결과, 실제 층 ordinal, 알 수 없는 위치 미연결, 첨부 3파일 해시·layout_version·목적지 fixture/층/node UUID 연결 검사가 통과했다. 이 검사는 실제 최단경로나 현장 배가를 인증하지 않는다.
- 기존 IndoorMapKitView·서가 레이블·카메라/스타일 코드 원본을 별도 iOS 검증 앱으로 컴파일했다. 실제 IMDF와 같은 목데이터 검색 결과를 전달해 iPhone 17 Pro / iOS 26.5에서 337-A 주황색 강조와 패널 위 카메라 맞춤을 확인했다. 이 검증 앱은 TCA 화면을 대체한 단순 호스트이므로 전체 BookRoutePreviewView의 통합 검증과 구분한다.
- 새 Swift 테스트 `BookRoutePreviewTests`에는 고정 목적지의 단일 강조·자동 포커스·Primo 조회 없음과 번들 파일 무결성/목적지 UUID 대조를 추가했다. 해당 테스트의 실행은 아래 Xcode 매크로 승인 문제로 아직 완료하지 못했다. 변경 파일의 Swift 문법 검사와 `git diff --check`는 통과했다.
- 현재 전체 앱 빌드 시도는 개인 키를 제외한 임시 사본에서 진행했고 기존 TCA·CasePaths·Dependencies·Perception·SwiftNavigation 매크로 활성화 승인 단계에서 중단됐다. 원본 프로젝트·패키지 잠금·전역 매크로 신뢰 설정은 바꾸지 않았다. 최신 실제 IMDF 미리보기의 전체 앱 빌드·화면 이동·렌더링 검수는 남아 있다.

### 앞선 다크 레이아웃 단계 기록

- 다크 레이아웃은 원본 Book·BookText·공통 BookCover 구현·BookRoutePreviewView를 별도 iOS 검증 앱으로 함께 컴파일하고 iPhone 17 Pro / iOS 26.5 시뮬레이터에서 렌더링했다. 샘플 Book만 전달했으며 실제 API·위치 요청은 실행하지 않았다.
- 기본 글씨 화면에서 버튼 줄바꿈과 상태바 겹침을 보정했다. 접근성 글씨 크기에서는 출발 버튼을 아래 줄로 내려 시간·단계·거리 영역의 폭을 확보한다.
- 실제 iOS Simulator SDK에서 원본 Book·BookText와 BookRoutePreviewView·BookBasketView의 타입 검사를 통과했다(Swift 5 / MainActor 기본 격리).
- BookDetailView 문법 검사, Xcode 프로젝트 plist 검사, git diff --check를 통과했다.
- 비밀 설정을 제외한 임시 사본의 전체 앱 빌드는 기존 잠금 파일의 xctest-dynamic-overlay 항목 누락으로 먼저 중단됐다. 임시 사본에서 의존성을 해석한 뒤에는 기존 TCA 등 패키지 매크로 활성화 확인에서 중단됐다. 원본 Package.resolved나 매크로 신뢰 설정은 변경하지 않았다.
- 전체 앱 빌드 성공·실제 화면 push/pop·바구니 선택 유지의 조작 검증을 완료한 것으로 취급하지 않는다. 위 확인 방법에 따른 GUI 검수는 남아 있다.
