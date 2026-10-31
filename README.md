# postech-library
포스텍 도서관 메인 어플리케이션

도서관·Yes24·정보나루의 공통 HTTP 계층과 API별 책임은 [도서 API 통신 구조](Docs/BookNetworking.md)를 참고하세요.

## 도서 API 중계 설정 (PLI-144)

프로젝트 루트의 `Base.xcconfig`를 Debug와 Release에서 공통으로 사용합니다.
이 파일은 Git으로 공유하며, 같은 폴더에 `Secrets.xcconfig`가 있으면 로컬 설정을 추가로 읽습니다.
Debug는 설정 없이 빌드할 수 있지만 실제 API 조회에는 개발 중계 토큰이 필요합니다.

실제 도서 검색을 사용하려면 프로젝트 루트에서 예시 파일을 복사합니다.

```sh
cp Secrets.example.xcconfig Secrets.xcconfig
```

생성한 `Secrets.xcconfig`에 서버 관리자가 발급한 `POBOOK_RELAY_TOKEN_DEVELOPMENT`를 입력합니다.
Primo·Yes24·정보나루 제공사 키는 서버에서만 보관하며 앱에 넣지 않습니다.
검색·추천·소장·소개·대체 표지 조회는 `BookAPIClient`를 공통 사용합니다.
응답 해석·앱 캐시는 유지하고 이미지 파일은 원본 URL에서 직접 다운로드합니다.

`Secrets.xcconfig`는 `.gitignore`에 등록된 개인 설정 파일입니다.
실제 키는 `Base.xcconfig`나 `Secrets.example.xcconfig`에 작성하지 않습니다.

| 배포 환경 | 서버 |
| --- | --- |
| Debug / 시뮬레이터 / 내부 Release | `pobook-api-dev.fpmaps.com` |
| 내부·외부 TestFlight | `pobook-api-testfligh.fpmaps.com` |
| App Store | `pobook-api.fpmaps.com` |

`testfligh`는 요청받은 도메인 철자입니다. 기본 `POBOOK_BUILD_CHANNEL=automatic`에서는
Release의 검증된 StoreKit `AppTransaction.environment`로 TestFlight(sandbox)와 App Store(production)를 구분합니다.
Xcode 배포 정보는 개발서버를 사용합니다. 영수증 파일 유무로 추측하거나 판별 실패 시 다른 서버로 우회하지 않습니다.
내부용 Release는 `POBOOK_BUILD_CHANNEL=internal`로 명시하며 Store/TestFlight 배포에 사용하지 않습니다.
Xcode Run은 Debug를 사용하세요. Release로 직접 실행하는 내부 빌드는 `internal`을 지정하세요.

Release의 `Validate API Relay Configuration` 단계는 자동 배포에
`POBOOK_RELAY_TOKEN_TESTFLIGHT`와 `POBOOK_RELAY_TOKEN_PRODUCTION`을 모두 요구합니다.
같은 바이너리가 TestFlight에서 App Store로 승격되므로 두 설정이 필요합니다.
내부 Release는 개발 토큰만 요구합니다. CI에서는 비공개 빌드 설정으로 같은 변수를 주입합니다.
앱에 포함된 중계 토큰은 추출 가능하며 사용자 인증이나 제공사 비밀키가 아닙니다.

현재 **세 서버 주소 모두 HTTPS·환경별 토큰·실호출 검증을 완료**했습니다.
세 호스트는 같은 중계 프로세스를 사용하며 제공사별 호출 한도를 합산합니다. 다른 환경의 토큰은 거절합니다.
운영자에게 받은 세 중계 접근 토큰을 로컬 제외 설정 또는 비공개 CI 설정에 주입해야 합니다.
일반 Release는 토큰 누락을 계속 차단합니다. 실제 TestFlight·App Store 설치본의 배포 판별은 아직 기기 검증이 필요합니다.
서버 운영·복구 절차는 [중계서버 안내](Server/api-relay/README.txt)를 참고하세요.

## 책의 서가 위치

검색 결과·책바구니·도서 상세의 `길안내 받기`에서 도서관 소장 정보의 청구기호로
3층 단행본·4층 제본학술지의 실제 서가를 찾아 지도에 표시합니다.
복수 소장처와 범위가 겹치는 후보는 보존하고, 지도에 없는 별치 구역은 미연결로 안내합니다.

소장 조회도 위와 같은 중계 환경을 사용합니다.
확인된 위치 코드와 검증 범위는 [책과 서가 연결](Docs/BookShelfMapping.md)을 참고하세요.

## 도서 상세와 책 소개

홈 → 도서 검색 → 검색 결과의 표지나 책 정보를 누르면 기본 상세 화면이 열립니다.
선택한 책의 ISBN으로 Yes24 상품 상세 API를 조회하고 책 소개와 원문 링크를 표시합니다.
ISBN13을 우선하며 ISBN10은 ISBN13으로 변환합니다. ISBN이 없거나 유효하지 않으면 요청하지 않습니다.
소개 없음과 조회 실패를 구분하며, 실패한 요청은 상세 화면에서 다시 시도할 수 있습니다.
검색 결과로 돌아오면 진행 중인 상세 조회를 취소하고 검색 결과와 책바구니를 보존합니다.

API 형식과 출처 표시는 [Yes24 상품 상세 API](https://developers.yes24.com/api-doc/goods-item-detail)와
[이용약관](https://developers.yes24.com/support/terms)을 기준으로 합니다.

## 표지 누락 보완

도서관 표지 URL이 없거나 이미지 로딩이 실패하면 같은 ISBN13의 Yes24 표지를 다시 조회합니다.
다른 판본의 표지는 사용하지 않으며, ISBN·상품·표지가 없으면 기존 ‘표지 없음’을 표시합니다.
위의 중계 토큰 설정을 사용합니다. [동작과 검증 방법](Docs/BookCoverFallback.md)을 참고하세요.
