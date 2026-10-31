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
