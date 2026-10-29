PLI-140 / GitHub #177 — 추천 하드데이터

파일
- 앱 임베드용: fingerprint-library/Resources/Recommendations/CuratedRecommendations.json
- 확인용: category-recommendations.csv / affiliation-recommendations.csv
- API 확인 근거: PrimoVerification.json
- 수량 및 JSON 해시: ValidationSummary.json

수량
- 카테고리 17개 × 12권 = 204개 항목.
- 학부 학과 13개 + 대학원 학과/과정 21개 + 교직원/아카데미 2개 = 소속 36개.
- 소속 36개 × 20권 = 720개 항목.
- 총 924개 추천 항목에서 고유 레코드 343개(ISBN 343개)를 재사용한다.
- 학부/대학원 같은 전공과 인접 전공은 관련 교재·입문서·교양서를 공유한다.
- 수량을 맞추기 위해 같은 그룹에 동일 레코드/ISBN을 중복 넣지 않는다.
- 다권본·전집은 하나의 서지 recordID를 추천 항목 1개로 센다. 실물 권수와는 다르다.
- 이 목록은 내부 알파용 분야별 큐레이션이다. 실제 대출 통계·대출 순위가 아니다.
  “학과별 많이 빌린 책”의 실제 통계로 표시하면 안 된다.

검증 조건
- 2026-10-29, POSTECH Primo API를 실제 호출했다.
- vid=82POSTECH_INST:82POSTECH / tab=LibraryCatalog / scope=MyInstitution.
- printed_book 필터와 skipDelivery=false로 후보를 검색했다.
- 최종 343개는 q=any,contains,<alma를 제외한 MMS 번호>, limit=20으로 각각 다시 조회했다.
- 응답 recordid가 해당 alma ID와 정확히 일치하는지 확인했다.
- PNX display.type=Printed_Book, deliveryCategory에 Alma-P가 있어야 포함했다.
- institution=82POSTECH_INST, libraryCode=MAIN이며 위치 코드와 청구기호가 있는 소장만 포함했다.
- PNX addata.isbn에서 체크섬이 유효한 ISBN13을 우선했다. 없으면 유효한 ISBN10을 ISBN13으로 변환했다.
- ISBN 누락/불량, 인쇄본 소장 누락, 청구기호 누락 후보는 제외하고 대체 후보를 검색했다.
- 검증 근거에는 정확한 요청 URL·시각·HTTP 상태·필수 응답 필드와 원본 전체 응답의 SHA-256을 남겼다.
  원본 전체 응답의 해시는 축약한 증거 JSON 자체의 해시가 아니다. 인증 키/헤더는 저장하지 않았다.
- 소장 존재 확인이지 현재 대출 가능 보장은 아니다. JSON availability는 조회 시점의 스냅샷이다.
- ISBN은 인쇄본 서지 레코드에 연결된 서지 ISBN이다. 권별/복본별 장정 ISBN까지 실물을 대조한 것은 아니다.

JSON 사용
- schemaVersion: 1.
- books: 고유 도서 배열. recordID로 인덱싱한다. 책의 서지·소장 정보는 여기 한 번만 저장한다.
- books[].book: 기존 Book 생성자와 같은 필드 이름/형식이다.
  id와 controlNumber는 모두 primo:<recordID>이며, ISBN은 13자리 문자열이다.
- books[].holdings: 기존 BookHolding 생성자와 같은 필드 이름/형식이다.
  holdingID(소장 ID)와 recordID(서지 ID)는 서로 다르다.
- categories: UserInterest.rawValue를 id로 사용한다. name, lccClasses, 순서 있는 recordIDs 12개를 보관한다.
- affiliations: PostechStatus와 학과 enum의 rawValue를 결합한 id를 사용한다.
  예: undergraduate.mathematics / graduate.mathematics / staff / appleDeveloperAcademy.
  name, status, department, profileDepartmentName, topics, 순서 있는 recordIDs 20개를 보관한다.
- 그룹 recordIDs를 books에서 조회한 순서가 표시 순서다. books 배열 자체의 순서는 표시 순위가 아니다.
- 현재 Book은 Decodable이 아니므로, 연결 담당자는 JSON용 Decodable DTO에서 기존 Book/BookHolding으로 변환해야 한다.
  기존 공통 Book 계약이나 앱 추천 로직을 이번 작업에서 바꾸지는 않았다.
- imageURL과 description은 null이다. 표지 다운로드/성공 여부는 이번 검증 범위가 아니다.
  앱의 기존 ISBN/recordID 기반 표지 조회를 연결하거나 기본 표지를 사용할 수 있다.
- JSON은 UTF-8이며 API 인증 없이 읽을 수 있는 정적 데이터다.
- 새 JSON 리소스만 추가했으며, 화면의 실제 추천 데이터 소스로 연결하지 않았다.

프로필 연결 주의
- 현재 UserProfile은 departmentName 문자열만 저장한다.
- 학부 수학과와 대학원 수학과는 모두 “수학과”로 저장되어 기존 프로필만으로 소속을 복원할 수 없다.
- 데이터는 두 소속 키를 분리해 보존했다. 자동으로 한 소속을 선택하는 로직은 추가하지 않았다.
- 레거시 departmentName만 있는 경우의 매핑 정책은 연결 작업에서 정해야 한다.

CSV
- UTF-8 BOM / RFC 4180 방식의 쉼표·인용부호·CRLF.
- 앞의 5열은 카테고리(또는 소속), 추천도서명, ISBN, 소장기호, ID다.
- 이어서 추천순서, Book.id, 저자, 소장위치, Primo URL, 검증일시, 그룹키를 제공한다.
- ID는 원본 alma recordID이며 Book.id는 primo: 접두사가 붙은 값이다.
- 소장이 여러 곳이면 소장기호/소장위치를 “ | ”로 구분했다. 개별 소장 필드가 필요하면 JSON을 사용한다.
- ISBN/ID는 식별자다. Excel에서 가져올 때 문자열 열로 지정하면 지수 표기를 피할 수 있다.

로컬 검증 (네트워크·비밀 키 불필요)
저장소 루트에서 다음을 실행한다. 아래 예시의 /private/tmp/pli140-check는 생성된 검증 산출물만 담는다.

mkdir -p /private/tmp/pli140-check
xcrun swiftc -module-cache-path /private/tmp/pli140-check/ModuleCache -parse-as-library \
 fingerprint-library/Domain/Book/Book.swift \
 fingerprint-library/Domain/Book/BookHolding.swift \
 fingerprint-library/Domain/Book/BookISBN.swift \
 fingerprint-library/Shared/BookText.swift \
 fingerprint-library/Clients/Book/PrimoHoldingsMapper.swift \
 fingerprint-library/Clients/Book/PrimoBookHoldingsService.swift \
 fingerprint-library/Domain/Postech/PostechStatus.swift \
 fingerprint-library/Domain/Postech/PostechDepartment.swift \
 fingerprint-library/Domain/Recommendation/UserInterest.swift \
 Scripts/verify-curated-recommendations.swift -o /private/tmp/pli140-check/verify
/private/tmp/pli140-check/verify

이 검증은 실제 생산 코드의 ISBN 해석·Book 생성·소장 mapper, 온보딩 enum의 전체 키/수량,
카테고리 LCC 일치, 참조 무결성, 그룹별 중복, API 근거와의 필드 일치를 확인한다.
불량 ISBN·중복 추천·빠진 소속·전자자료뿐인 근거를 거부하는 음성 테스트 4개도 실행한다.
실제 앱 전체 빌드·화면 연결·서가 fixture 매칭/길찾기·현재 재고/대출 상태·표지는 별도 검증이 필요하다.

API 명세
https://developers.exlibrisgroup.com/primo/apis/docs/primoSearch/R0VUIC9wcmltby92MS9zZWFyY2g%3D/
개별 도서의 POSTECH 링크와 정확한 검증 요청은 CSV/JSON 및 PrimoVerification.json에서 확인할 수 있다.
