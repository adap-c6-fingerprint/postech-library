# 책 표지 누락 시 Yes24 재조회 (#174)

이번 변경 범위는 표지 데이터 보완이다. 저자·설명 보완이나 화면 디자인은 변경하지 않는다.

## 동작

1. 도서관 표지 주소가 있으면 기존 공통 이미지 로더로 먼저 읽는다. 정상 표지는 그대로 사용한다.
2. 주소가 없거나 이미지 로딩이 실패하면 책의 ISBN을 검증·정규화하고 Yes24 상품 상세 API를 조회한다. ISBN10은 기존 `BookISBN` 규칙으로 ISBN13으로 변환한다.
3. 응답 중 **ISBN13이 정확히 같은 항목**의 HTTPS `cover` 주소만 사용한다. 제목 검색으로 다른 번역·출판사의 판본을 추정하지 않는다.
4. ISBN 없음, 상품 미등록, 다른 ISBN 응답, 표지 주소 없음은 기존 ‘표지 없음’ 상태로 표시한다. API·이미지 전송 오류는 기존 재시도 가능한 실패 상태로 표시한다.

검색·추천·상세·책바구니·경로 미리보기·지도·도착 화면 표지가 같은 처리 경로를 사용한다. 기존 뷰에는 ISBN 전달만 추가했고 크기·배치·버튼은 유지했다.
`Book` 계약과 원본 표지 URL은 바꾸지 않는다. 표지 대체 처리는 공통 로더 내부에서 이루어진다.

동일 ISBN의 진행 중 Yes24 조회를 공유한다. 성공·미등록 결과는 15분 동안 최대 100개를 메모리에 보관하고, 오류는 보관하지 않는다.
이미지 다운로드·완료 캐시는 기존 `SharedImageLoader`를 재사용한다. PLI-144부터 Yes24 메타데이터는 `BookAPIClient`로 중계하고 이미지는 원본 URL을 사용한다. 제공사 키는 서버에만 둔다. [환경 설정](../README.md)을 참고한다.

계약 출처: [Yes24 상품 상세 API](https://developers.yes24.com/api-doc/goods-item-detail).
`searchType=ISBN13`, `query`, `X-Api-Key`, `data.items[].isbn13`, `cover`를 사용한다.
제공자가 실제 표지 대신 대체 이미지를 반환하는 경우를 판별하는 별도 필드는 없다. 파일명·크기만으로 표지 여부를 추측하지 않는다.

## 실서버 확인

2026-10-29 Primo에서 확인한 『1984』 다섯 판본의 4libs 표지 URL은 HTTP 403을 반환했다.
같은 ISBN으로 Yes24를 조회하고 **실제 앱 서비스·모델 소스**를 실행해 이미지 다운로드 및 디코딩 후 `loaded` 상태에 도달하는 것을 확인했다.

| ISBN13 | Yes24 상품 번호 | 결과 |
| --- | --- | --- |
| 9791185042022 | 8778724 | loaded |
| 9788931022728 | 108893509 | loaded |
| 9788964600955 | 4240387 | loaded |
| 9788937460777 (원본 ISBN10 8937460777) | 372300 | loaded |
| 9788998244545 | 8909469 | loaded |

ISBN과 표지가 모두 없는 레코드는 같은 판본을 확인할 수 없어 `unavailable`을 유지했다.
이 결과는 위 판본과 확인 시점에 대한 근거이며 전체 도서의 표지 존재를 보장하지 않는다.

## 검증 재현

Postman CLI의 소유자 모의 서버 검색은 로그인 부재로 수행하지 못해 공식 API 계약에 근거한 로컬 모의 서버를 만들었다. 외부에 배포·게시하지 않는다.
모의 응답의 ISBN별 실패 조건과 PNG는 검증용이며 해당 책의 실서버 응답을 뜻하지 않는다.

첫 터미널에서 모의 서버를 시작한다. 매 실행 전 서버를 새로 시작해야 503 1회 실패 카운터가 초기화된다.

```sh
postman simulation run postman/simulations/book-cover-fallback.sim.yaml --port 4174 --no-history --output ndjson
```

다른 터미널에서 실제 서비스·표지 모델 소스를 함께 컴파일해 실행한다.

```sh
./Scripts/verify-book-cover-fallback.sh
```

URL 누락, 도서관 403/404, 다른 ISBN 거부, 미등록, 표지 null, API 503 및 재시도, ISBN 누락의 9개 경로를 확인하고 HTTP 호출 횟수를 검사한다.
모의 서버의 `request` 기록에서도 의도한 경로가 실행됐는지 확인한다. 이 검증의 이미지 디코더는 macOS AppKit이며 iOS UIKit 디코딩과는 별도다.
로컬 `Secrets.xcconfig`의 개발 중계 토큰을 이용한 실제 『1984』 조회는 다음과 같다.

```sh
./Scripts/verify-book-cover-fallback.sh --live
```

iPhone 18 Pro / iOS 27.0의 `BookCoverFallbackTests`, `Yes24BookCoverTests`, 기존 `BookDetailClientTests`, `BookCoverModelTests`, `SharedImageLoaderTests`도 통과했다.
현재 기본 스킴의 별도 `BookBasketIsolationTests.swift`는 기존 main actor 격리 `Equatable` 컴파일 오류가 있어,
검증 명령에서 `EXCLUDED_SOURCE_FILE_NAMES=BookBasketIsolationTests.swift`로 그 파일만 제외했다. 전체 테스트 통과로 간주하지 않는다.
