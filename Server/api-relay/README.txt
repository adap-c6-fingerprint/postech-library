PLI-144 / GitHub #182 — 개발용 단순 API 중계 (단계 1)

범위
- Node 22 표준 라이브러리만 사용한다. npm 의존성·DB·Redis·응답 캐시 없음.
- 앱 코드는 아직 바꾸지 않는다. 추천/검색/길안내 계산과 이미지 다운로드는 앱에 남는다.
- 운영 도메인 pobook-api.fpmaps.com은 이번 배포 대상이 아니다.

계약 (모두 GET)
- /healthz: 공개, 외부 호출 없는 프로세스 상태. 공급자 연결 상태를 보장하지 않는다.
- /primo/v1/search: 기존 Primo 검색 쿼리와 원본 JSON/오류를 전달한다.
- /yes24/v1/goods/itemDetail: searchType=ISBN13, query=ISBN13.
- /data4library/api/srchDtlList: isbn13, format=json.
- /data4library/api/recommandList: isbn13, type=mania, format=json.
- /healthz 외에는 Authorization: Bearer <RELAY_TOKEN>이 필요하다.
- 이 토큰은 개발용 무단 호출 억제 수단이다. 배포 앱에 넣는 고정 토큰은 강한 사용자 인증이 아니다.
- 전달 대상 URL/기관/허용 파라미터는 고정한다. 클라이언트 제공 apikey/authKey는 거절한다.
- 앱의 q 인코딩/OR/와일드카드, 페이지, multiFacets는 기존 의미를 보존한다.
- 응답 본문/상태/Content-Type, Retry-After, X-Exl-Api-Remaining을 유지한다.
- Set-Cookie, Location, 외부 인증 헤더를 앱으로 전달하지 않는다.
- 리다이렉트는 추적하지 않는다. 중계 실패 502, 시간 초과 504, 로컬 제한 429.
- 최대 응답 4MiB, 외부 요청 총 12초. 응답을 읽는 동안에도 제한한다.
- 자동 재시도 없음: 기존 앱의 재시도와 중첩하지 않는다.
- Accept는 Primo만 application/json, Yes24/정보나루는 */*로 기존 호출 의미를 유지한다.
  정보나루는 format=json이어도 Accept: application/json이면 406을 반환함을 실호출로 확인했다.
- Cache-Control: no-store. Cloudflare의 해당 호스트 캐시 규칙도 별도 확인해야 한다.

개발용 보호 한도
- 동시 요청: Primo 4 / Yes24 2 / 정보나루 10.
- 초당 요청: Primo 10 / Yes24 5 / 정보나루 10.
- 24시간 예산: Primo 1500 / Yes24 1000 / 정보나루 400.
  정보나루 고정 IP 등록 여부를 확인하기 전에는 500건 미만으로 제한한다.
- 한도는 공급자의 실제 잔여량이 아니다. 동일 키를 쓰는 앱/다른 서비스 호출은 포함하지 않는다.
- 카운터는 단일 프로세스 메모리이며 재시작 시 초기화된다. 복제/운영 전환 전에는 공유 집계가 필요하다.
- 원문 검색어/IP/토큰/외부 URL/응답은 기록하지 않는다. provider/status/durationMs만 기록한다.

로컬 검사
- node --test Server/api-relay/relay.test.mjs
- 비밀값 없는 모의 외부 응답으로 인증·입력·본문·상태·헤더·취소·제한을 확인한다.

배포 구성
- 서버 디렉터리: /home/ubuntu/pobook-api-dev
- Docker Compose project: pobook-api-dev, container: pobook-api-dev.
- 기존 webnet 네트워크에서 nginx-proxy가 내부 3000 포트에 연결한다. 공개 포트는 추가하지 않는다.
- 0.5 CPU / 512MiB / 64 PID, non-root, read-only, cap_drop ALL, no-new-privileges.
- private/credentials.json은 Git/build context에서 제외하고 read-only로 마운트한다.
- credentials.json: RELAY_TOKEN, PRIMO_API_KEY, YES24_API_KEY, DATA4LIBRARY_API_KEY.
- private 디렉터리 0700, 파일 0600. 실행 UID/GID는 파일 소유자와 일치시킨다.
- .env에는 RELAY_UID, RELAY_GID, RELAY_VERSION만 둔다. 외부 API 키를 Compose 환경에 넣지 않는다.
- 초기 키 주입은 provision-credentials.mjs의 stdout을 SSH로 서버 private 파일에 직접 연결한다.
  절대 터미널/로그로 실행하지 않는다. 기존 파일을 덮어쓰지 않도록 검사한다.
- Node 기반 이미지는 digest 고정. 외부 의존성이 없고 Dockerfile COPY도 세 파일로 제한한다.

Nginx/인증서
- 기존 /home/ubuntu/nginx-proxy/nginx.conf의 http {}에 개발 호스트만 추가한다.
- deploy/nginx-http.conf로 HTTP ACME 경로를 먼저 연결하고 인증서를 발급한다.
- 인증서 이름: pobook-api-dev.fpmaps.com. 기존 /home/ubuntu/letsencrypt 저장소 사용.
- deploy/nginx-https.conf를 추가한다. 기존 블로그/Kutt/운영 API 호스트는 변경하지 않는다.
- nginx -t 통과 후 graceful reload. 실패하면 reload하지 않고 원본 파일로 복구한다.
- API 호스트 access log는 끄고 error log도 원문 요청이 남지 않게 비활성화한다.
- 인증서 갱신 작업은 개발 인증서만 대상으로 설치한다. 기존 인증서를 일괄 갱신하지 않는다.
- Cloudflare Full(strict), 캐시 우회, 네이티브 앱에 HTML 챌린지를 내리지 않는지는 계정에서 확인 필요.

복구
- 새 컨테이너만 중지하려면 해당 디렉터리에서 docker compose -p pobook-api-dev stop api.
- 기존 서비스 전체의 compose down/restart/prune는 실행하지 않는다.
- 원본 Nginx 백업과 현재 설정을 비교한다. 배포 후 다른 변경이 있으면 전체 백업을 덮어쓰지 않는다.
- 이번에 추가한 두 server 블록만 제거한 사본을 nginx -t로 검증 후 적용/reload한다.
- API 전용 cron을 제거하면 갱신이 중단된다. 인증서/키는 필요하면 보관한다.
- 삭제나 디스크 정리는 이 작업에 포함하지 않는다.

다음 단계
- 앱의 공통 중계 Client와 주소/접근 토큰 설정을 연결한다.
- 외부 제공사 키를 앱에서 제거하되 기존 Mapper와 UI/앱 캐시를 유지한다.
- 제공사 키가 실제 운영 키인지, 정보나루 서버 IP가 등록됐는지 사람이 확인한다.
- 개발 토큰은 채팅이나 PR에 붙이지 않고 승인된 비밀 전달 경로로 공유한다.

단계 1 배포 확인 (2026-10-31)
- 기준 dev: bd908b168ec94e035f3f0cf6a4282387f561f5d8.
- 실행 이미지: pobook-api-dev:be40821 (Node v22.23.2 / ARM64).
- https://pobook-api-dev.fpmaps.com/healthz -> 200 {"status":"ok"}.
- 개발 도메인을 통한 Primo / Yes24 / 정보나루 상세 / 정보나루 연관 도서: 모두 200, 정상 자료 구조 확인.
- 인증 누락 401, 미허용 경로 404, 키 덮어쓰기 파라미터 400 확인.
- 모든 smoke 응답의 Cache-Control no-store, Cloudflare DYNAMIC 확인.
- 로컬 Node 22.22.1 및 서버 ARM Node 22.23.2의 모의 단위 테스트 17개 각각 통과.
- 기존 Nginx 설정은 변경 없이 유지하고 개발용 HTTP/HTTPS server 블록 두 개만 추가했다.
- 원본 백업: /home/ubuntu/nginx-proxy/nginx.conf.before-pobook-api-dev-20261031.
- 최종 Nginx sha256: 42f6d754f1db3f97789f2b7bb2dd91373c758fb4062b6518c0691049acf7888a.
- nginx -t 통과, graceful reload. 기존 서비스 컨테이너 재시작 없음.
- john-baek.com 200 / blog.fpmaps.com 200 / set-link.fpmaps.com 302 확인.
- 운영 API 도메인은 기존과 동일하게 블로그로 301. 운영 환경은 배포하지 않았다.
- 별도 joinmyorder.pm-z.com / news.pm-z.com HTTPS 526을 발견했으나 수정하지 않았다.
  사전 상태와의 응답 비교는 없고, 관련 기존 Nginx 블록은 전후 diff에서 동일함을 확인했다.
- 개발 인증서 만료일 2027-01-29. 전용 cron 설치와 certbot 모의 갱신 성공 확인.
- 컨테이너 healthy / 재시작 0. 유휴 관측 CPU 0%, RAM 약 17MiB (최대 부하 측정이 아님).
- 앱/빌드 설정 변경 없음. 앱 연결·장기 부하·제공사 실제 할당량·Cloudflare 계정 설정 검증은 남는다.
- 비밀 파일은 서버에만 추가했다. 기존 앱 키 제거는 단계 2 범위다.
- GitHub push/PR/merge 및 Linear 완료 처리는 하지 않았다.

셀프리뷰
- 영향도 M: 신규 개발 API 경로·배포·인증 경계에 한정하며 앱/운영 도메인 계약은 변경하지 않는다.
- 고정 upstream, 파라미터 검사, 키 주입, 원본 상태/본문 보존, 취소/상한/타임아웃,
  키 없는 build context, 파일 권한, 자원 제한 및 기존 Nginx diff를 검토했다.
- 개발 1단계 범위에서 필수 수정 문제는 남기지 않았다. 운영 전환 승인이나 사람 리뷰를 대신하지 않는다.
- 메모리 카운터/고정 개발 토큰의 제약은 위에 명시했다. 복제/운영 인증으로 사용하지 않는다.

단계 2 — 앱 호출 통합 (2026-10-31)
- BookAPIClient가 고정된 네 중계 경로, 환경별 호스트와 Bearer 인증을 담당한다.
- 공급자별 쿼리/디코딩/오류/재시도와 UI/추천/모델/캐시는 유지한다. 이미지는 원본 URL을 사용한다.
- 앱 Info.plist와 기본 설정에서 제공사 키 및 기존 PRIMO_PROXY_URL을 제거했다.
- Debug/시뮬레이터/명시적 내부 Release -> pobook-api-dev.fpmaps.com.
- 검증된 StoreKit sandbox(TestFlight 내부/외부) -> pobook-api-testfligh.fpmaps.com.
- 검증된 StoreKit production(App Store) -> pobook-api.fpmaps.com.
- testfligh는 사용자 지정 철자다. 영수증 파일명으로 추측하거나 환경 오류에 다른 서버로 우회하지 않는다.
- 내부 Release는 POBOOK_BUILD_CHANNEL=internal. Store/TestFlight archive는 automatic을 사용한다.
- 자동 Release는 TESTFLIGHT/PRODUCTION 두 접근 토큰을 요구하고 내부 Release는 DEVELOPMENT만 요구한다.
- 서버/인증서 변경은 없다. TestFlight/운영 서버와 토큰은 아직 미구성 상태이며 일반 Release archive를 차단한다.
- 로컬 Git 제외 Secrets.xcconfig(0600)에 개발 접근 토큰만 연결했다. 제공사 키는 가져오지 않았다.
- 중계 토큰은 앱에서 추출 가능하다. 이 설정을 강한 운영 인증으로 취급하지 않는다.

단계 2 검증
- Python 설정/자료 검사 21개 통과.
- BookDetailTests 223개 / 39개 suite 통과, Xcode TEST SUCCEEDED.
- 환경 선택, 토큰/쿼리 검증, 원본 상태/본문/Retry-After 보존, 검색 조건과 공급자별 해석을 확인했다.
- 실제 앱 HTTPClient/BookAPIClient/공급자 Client로 개발 HTTPS 4개 경로를 각각 한 번 호출: 모두 200 및 기존 JSON envelope 확인.
- 빌드 산출물 Info.plist에 제공사 키 설정 0개, 개발 토큰 주입 확인. 값은 로그에 출력하지 않았다.
- 대체 표지 모의 검증: 9개 경로 및 중복 조회 방지/실패 후 재시도 횟수 검사 통과.
- 소장 정보 모의 검증: 소장처 보존·정확한 자료 번호·빈 결과·401·잘못된 JSON·503 상한·429 복구 통과.
- 현 SDK 26.5에는 기존 BookDetailView.contentMarginsRemoved(iOS 27)가 없어 원본 빌드는 실패했다.
  저장소 코드는 수정하지 않고 해당 한 줄만 제거한 /private/tmp 사본을 VFS overlay로 사용했다.
- 기존 BookBasketIsolationTests.swift와 *ScreenTests.swift는 기존 컴파일 문제로 제외했다.
- 전체 테스트 시도는 별도 IndoorLocationAuthorizationMonitorTests의 offMainThread 단언 실패와
  테스트 보조 프로세스의 simctl 조회 실패가 있어 통과로 판단하지 않는다. 위 도서 테스트는 분리 재실행 결과다.
- 실제 기기의 TestFlight/App Store 배포 판별, 전체 UI 회귀, 장기 부하, 운영 보안/할당량 검증은 남는다.

실제 개발 중계 Client 검증 재현 (프로젝트 루트, Xcode 선택 후 실행)
  xcrun swiftc -swift-version 6 -parse-as-library \
    fingerprint-library/Clients/Network/HTTPClient.swift \
    fingerprint-library/Clients/Network/BookAPIClient.swift \
    fingerprint-library/Shared/AppConfiguration.swift \
    fingerprint-library/Clients/Book/Client/PrimoAPIClient.swift \
    fingerprint-library/Clients/Book/Client/Data4LibraryAPIClient.swift \
    Scripts/verify-api-relay.swift -o /tmp/pobook-relay-proof
  /tmp/pobook-relay-proof
이 검증은 개발 토큰을 로컬 제외 파일에서 읽고 실제 제공사 할당량을 각각 1회 사용한다.
