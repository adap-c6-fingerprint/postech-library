# 책의 청구기호와 실제 서가 연결

이슈 [#75](https://github.com/adap-c6-fingerprint/postech-library/issues/75)의 범위는
선택한 책의 소장 정보에서 청구기호를 읽고 해당 서가를 지도에 표시하는 것이다.
`dev`의 `860fcdb`에서 `feat/#75-book-shelf-location`을 분기하고, 아직 dev에 없는
#53의 서가 인덱스·레이블 표시 코드를 로컬 병합해 사용한다. 게시 전 `7079c5e`의 최신 dev도
병합해 별도 검색 탭·표지 캐시 변경을 유지했다. 선행 PR #68은 아직 열려 있어
현재 dev 기준 PR에는 그 서가 표시 기반 변경도 포함된다.

## 연결 흐름

1. 기존 `Book.controlNumber` 또는 `Book.id`에서 `primo:alma…` / `alma…` 자료 번호를 확인한다.
   공유 `Book`과 `BookClient` 계약은 변경하지 않는다. ISBN·제목으로 다른 판본을 추정하지 않는다.
2. `BookHoldingsClient`가 위치 정보를 별도로 조회한다. `GET /primo/v1/search`에
   `q=any,contains,{MMS 번호}`, `skipDelivery=false`, POSTECH vid·tab·scope를 보낸다.
3. `PrimoHoldingsMapper`가 검색 결과의 `pnx.control.recordid`를 정확히 대조한 뒤
   `delivery.holding[]`에서 기관·도서관·소장 위치 코드·청구기호·소장 ID·대출 상태를 읽는다.
4. `BookHoldingShelfResolver`가 확인된 일반 서고의 층을 정하고 `BookShelfRangeMatcher`로
   해당 층의 청구기호 범위를 검색한다.
5. `BundledShelfLabelLoader`가 이미 연결한 `fixtureNumber` → IMDF fixture의 복합 ID
   (`kind`, `sourceID`)를 사용해 실제 도형과 서가 번호·면을 주황색으로 강조한다.

`holdingID`는 소장처 식별자이고 `fixtureNumber`는 지도 책장 이름이다. 서로 같은 값으로 취급하지 않는다.
지도 표시는 서가 도착 노드나 이동 경로를 만들지 않는다.

## 실제 API에서 확인한 내용

2026-10-28 POSTECH 읽기 전용 응답으로 확인했다.

- 소장 정보는 PDF 표의 `pnx.delivery.holding`이 아니라 최상위 `delivery.holding`에 있었다.
- 소장 ID는 `holdId`, 위치 코드는 `subLocationCode`, 표시 이름은 `subLocation`이었다.
- `rid,exact,alma991000958759703286`은 결과가 없었고, MMS 번호의 `any,contains` 검색은
  같은 레코드를 반환했다. 이 관찰을 전체 기관의 일반적인 Primo 계약으로 확대하지 않는다.
- 박태준학술정보관(`82POSTECH_INST` / `MAIN`)에서 `c3b`는 3층 단행본,
  `c4b`는 4층 제본학술지였다. `c4c`(신착학술지)는 같은 층이어도 이 범위표로 연결하지 않는다.
- 『사피엔스』(`alma991000958759703286`)에는 일반 서고, 스마트도서관,
  2층 권장도서 구역의 소장처가 함께 있었다. 동일 청구기호만으로 모두 일반 서고에 배정하면 안 된다.

문서 변형인 `pnx.delivery`와 `holdingId`도 읽는다. 구조화된 소장 정보가 없을 때에만
`pnx.display.availlibrary`를 대체로 사용한다. 공식 PNX의 `$$I`=기관, `$$L`=도서관,
`$$1`=소장 위치, `$$2`=청구기호, `$$S`=상태, `$$Z`=위치 코드로 해석하고 `$$9ONLINE`은 제외한다.
명시적인 빈 holding 목록에 bestlocation이나 대체 필드의 과거 위치를 섞지 않는다.

공식 참고: [Primo Search](https://developers.exlibrisgroup.com/primo/apis/search/),
[PNX 소장 정보 규격](https://developers.exlibrisgroup.com/primo/integrations/frontend/rta/).
기관별 계약의 원본은 사용자가 제공한 `POSTECH 도서관 API 정보.pdf`다. 인증 키는 저장소에 복사하지 않는다.

## 후보와 실패 처리

- 범위의 시작·끝은 기존 사용자 확인대로 `callStart` → `callEnd`다.
- 양 끝을 포함하고 겹치는 후보를 모두 보존한다. 경계 포함 규칙이 확정되기 전에는
  배열 첫 항목을 실제 서가 하나로 단정하지 않는다. 화면에도 후보 서가임을 표시한다.
- 여러 소장처·여러 층을 보존한다. 같은 도형의 강조는 중복하지 않고 책별 소장 정보는 유지한다.
- 스마트도서관·권장도서·신착학술지·알 수 없는 기관/위치 코드는 원래 정보를 보여주고 미연결로 안내한다.
- 청구기호 누락, 인덱스 밖/해석 불가, 소장 정보 없음, 네트워크 실패를 구분한다.
- 범위 없는 `other` 구역과 빈 서가를 모든 도서에 맞는 범위로 해석하지 않는다.

## 화면과 수명

검색 탭·지도 탭의 책바구니와 도서 상세의 `길안내 받기`에서 같은 위치 지도를 연다.
바구니의 기존 1~3권 제한과 입력 순서는 유지한다. 각 후보 버튼은 해당 층·책장에 포커스하며,
`모두 보기`는 현재 층의 후보 전체에 맞춘다. 다른 층 후보는 해당 후보 버튼으로 이동한다.
독립된 지도 상태를 사용해 뒤로 갔을 때 검색·바구니·홈 지도·상세 화면 상태를 보존한다.

지도와 소장 정보 중 어느 쪽이 먼저 와도 연결을 갱신한다. 요청 번호로 오래된 응답을 무시하며,
화면을 닫으면 TCA presentation 수명에 따라 위치 요청을 취소한다. 실패는 다시 시도할 수 있다.
성공한 위치 정보는 추천 카드와 공유하는 캐시에 최대 1분·200건 보관하고 실패 응답은 캐시하지 않는다.
대출 상태는 실시간 배가 보증으로 표시하지 않는다. HTTP 429/5xx는 최대 3회 요청하고
0.5초·1초 지수 백오프를 적용한다. 수치 Retry-After가 5초 이하면 그 이상을 기다리고,
더 길면 재시도를 중단해 서버가 요구한 간격을 어기지 않는다.

## 프록시 설정

기관 문서는 API 키를 백엔드 프록시에 보관하도록 요구한다.
`Secrets.xcconfig`의 `PRIMO_PROXY_URL`에 HTTPS 프록시 기본 주소를 설정하면
소장 조회는 그 주소의 `/primo/v1/search`를 호출하며 앱의 Primo 키를 전송하지 않는다.
프록시는 기관 키·사용자 인증·요청 제한을 서버에서 관리해야 한다. 프록시 배포 주소는 아직 제공되지 않았다.

```xcconfig
// xcconfig의 // 주석 처리를 피한다. 아래는 실제 서버가 아닌 설정 형식 예시다.
PRIMO_PROXY_URL = https:/$()/library.example.org
```

Debug에서 프록시를 설정하지 않으면 기존 로컬 `PRIMO_API_KEY`로 개발용 조회를 할 수 있다.
Release의 새 소장 조회는 프록시 없이 실패한다. 기존 검색·추천 클라이언트의 직접 호출 구조는
이번 이슈에서 바꾸지 않았으므로 앱 전체의 배포용 키 관리는 별도로 점검해야 한다.

앱 타깃의 `Validate Release Primo Proxy` 빌드 단계가
`Scripts/validate-release-configuration.py`로 Release의 실제 빌드 설정을 검사한다.
누락·미치환 변수·HTTP·사용자 정보·쿼리·fragment가 있는 주소는 빌드 오류로 처리해
설정 없이 배포한 뒤 위치 조회가 실패하는 경로를 막는다. Debug에는 프록시를 강제하지 않는다.
주입 경로는 로컬의 Git 제외 `Secrets.xcconfig` 또는 배포 명령의 명시적인
`PRIMO_PROXY_URL="$POSTECH_PRIMO_PROXY_URL"` 빌드 설정이다. 명령 예시는 README에 있다.
프록시 운영 주소는 아직 확인되지 않았으며 주소 형식·빌드 주입 검사와 실제 서비스 배포 완료는 구분한다.

PR 리뷰 보완 검증에서 프록시 없는 Release 빌드가 설정 오류로 중단되는 것을 확인했다.
검증용 `.invalid` HTTPS 주소를 명시적인 빌드 설정으로 주입하면 Release Simulator 빌드와
생성된 `Info.plist`의 값 전달이 통과했다. 이는 운영 서버 접속 검사가 아니다.
프록시 없는 Debug의 파싱 테스트는 7개 함수·13회 실행, Python 자료·설정 검사는 20개가 통과했다.
파싱 결과 번들은 `/private/tmp/postech-issue75-review-final.xcresult`다.

식별 정보가 없는 비대상 문서는 정상 대상의 위치 조회를 막지 않도록 `pnx`·`control`·`recordid`의
누락·null을 불일치로 처리한다. API 오류 객체처럼 `docs` 자체가 잘못된 응답은 계속 오류로 처리한다.

## 검증

`PrimoHoldingsMapperTests`, `BookHoldingShelfResolverTests`, `BookHoldingMapFeatureTests`와
기존 지도 feature/screen 회귀 테스트로 파싱, 층 제한, 중복·경계 후보, 실패·재시도·취소,
화면 재진입과 상세 진입을 검증한다. 실제 기기에서 책이 해당 칸에 배가됐는지는 별도 현장 확인 대상이다.

2026-10-28 iPhone 18 Pro / iOS Simulator 27.0에서 전체 **200개 테스트 함수·352회 실행**이
통과했다. 실패·skip·xcresult 런타임 경고는 0이다. 결과 번들은
`/private/tmp/postech-issue75-verified.xcresult`다. 단일 책·3권 지도와 다크 모드의 화면 이미지도 확인했다.
새 HTTP 서비스·파서·서가 연결 규칙은 별도 Swift 6 언어 모드 실행으로도 검증했다.
기존 추천 클라이언트의 `foundationModelsClient` actor-isolation 빌드 경고는 본 변경과 별개로 남아 있다.

같은 날 완성된 Swift 서비스로 실제 API를 조회하고 저장소의 IMDF·서가 인덱스를 읽어
『사피엔스』가 `CB113.H4 .H3713 2015` → `3층 306-A` → `S-3F-502-A` →
fixture UUID `0E33F533-1812-41C3-AD83-5D71DD3AC21E`로 연결됨을 확인했다.
함께 반환된 스마트도서관·2층 권장도서 소장처는 미연결 상태를 보존했다.

로컬 개인 프로젝트는 앱 iOS 27·테스트 iOS 26 설정이 달라, 테스트는 현재 소스를 복사하고
Git에 저장된 기존 프로젝트 설정을 적용한 검증 사본에서 실행한다. 개인 Xcode 설정과 키는 변경하지 않는다.
HTTP 검증 명령·mock 출처·한계는
[Primo 시뮬레이션 실행 기록](../postman/simulations/primo-holdings/primo-holdings.context.md)에 있다.

기존 `BookShelfResolver`와 C5 fixture 테스트는 명시적으로 전달한 `ShelfKey`를
길찾기 디렉터리에 연결하는 별도 규칙이며 그대로 보존한다. 이번 실제 위치 표시에는
길찾기 노드가 없는 IMDF fixture를 사용한다.

### 최신 dev 통합 후 게시 검증

`7079c5e`의 검색 탭 분리·추천/표지 캐시 변경을 병합하고, 검색 탭의 결과·바구니에서도
서가 지도를 표시하도록 연결했다. 지도 탭과 검색 탭 양쪽의 화면 진입·뒤로가기·3권 표시는 통과했다.
전체 260개 테스트 함수·429회 실행 중 258개 함수·427회가 통과하고 2개가 실패했다.
실패·skip·경고를 통과로 합산하지 않는다. skip과 xcresult 런타임 경고는 0이다.
결과는 `/private/tmp/postech-issue75-publish-tests.xcresult`다.

실패한 항목은 `HomeRecommendationCacheTests.connectsAlgorithmToHomeAndCache(hasCached:)`와
`preservesDisplayOnFailure(hasCached:)`의 캐시 없음 분기다. 변경 없는 dev `7079c5e`에서도
동일한 두 실패를 재현했다. 상태가 바뀌지 않는 `recommendationsRestored`에 상태 변경 검증
클로저를 전달해 TCA가 `Expected state to change, but no change occurred`를 보고한다.
두 테스트와 `HomeFeature`는 본 PR에서 변경하지 않았다. 기준 브랜치 검사 결과는
`/private/tmp/postech-issue75-dev-baseline.xcresult`다. 전체 검증 완료 판정은 이 기존 실패의
해결 또는 팀의 검증 기준 확인 후에 내린다. Python 자료 검사 16개는 통과했다.
