# 도서 담당 범위의 의존성·책임 분리

2026-10-30 기준. 사용자 목록의 🏔️ 파일과 별도 지정한 `BookFavoritesClient.swift`를 점검했다.
파일의 길이나 의존성 개수보다, 변경 이유가 다른 책임이 한곳에 모였는지를 기준으로 판단했다.

## 담당 파일별 결과

| 파일 | 판단과 조치 |
| --- | --- |
| `BookFavoritesClient.swift` | 미사용 코드 없음. load는 검색·홈·상세·추천에서, save는 검색·상세에서 사용한다. userDefaults(suiteName:)는 실제 구현과 격리 저장 테스트에서 사용한다. 저장 책임에 집중하므로 유지한다. |
| `BookClient.swift` | 조회 조합과 응답 변환이 섞여 있었다. 연도·출판사·서지/소장 위치 변환 및 DTO를 PrimoBookMapper로 분리했다. 기존 조회 인터페이스와 변환 오류 메시지는 유지한다. 호출되지 않는 이전 invalidURL·apiError 오류 분기도 제거했다. |
| `ColdStartRecommendationClient.swift` | 페이지 선택·표지 조회·이미지 검사·배치 선정·Primo/정보나루 DTO가 모여 있었다. 추천 진행 흐름만 남기고 아래 경계로 분리했다. |
| `PersonalizedRecommendationClient.swift` | 모델 추천 흐름과 응답/표지 처리가 섞였고, 첫 추천 서비스 내부 함수·DTO·오류 타입을 참조했다. 공통 변환·표지 경계와 공유 설정 오류를 사용하도록 바꿨다. |
| `BookRecommendationClient.swift` | 첫 추천/맞춤 추천 선택·실패 대체·메타데이터 보완을 조합하는 역할이다. 현재는 추가 분할하지 않는다. |
| `BookDetailClient.swift` | Yes24 소개 조회의 설정·전송 의존성을 조합하는 작은 경계다. 유지한다. |
| `BookHoldingsClient.swift` | 프록시/Debug 직접 인증 선택과 짧은 소장 캐시를 조합한다. 서비스·매퍼가 이미 분리되어 있어 유지한다. |
| `PrimoBookHoldingsService.swift` | 소장 조회의 자료 번호 검증·재시도 정책을 담당한다. 응답 변환은 별도 매퍼를 사용하므로 유지한다. |
| `PrimoHoldingsMapper.swift` | 소장 응답 변환에 집중한다. 유지한다. |
| `RelatedBooksClient.swift` | ISBN 기반 연관 도서 조회 경계다. 디자인 대기 중인 기능으로 사용자가 유지하도록 지정했다. API 호출·상태·테스트를 보존한다. |
| `Yes24BookDetailService.swift` | 동일 상품 조회에서 소개·표지를 해석하고 제공자 오류 규칙을 적용한다. 조회 중복 구현 없이 응집되어 있어 유지한다. |
| `BookHoldingPresentation.swift` | 표시할 대표 소장처를 선택하는 단일 규칙이다. 유지한다. |
| `BookDetailFeature.swift` | 소개·소장·연관 도서의 독립 상태와 화면 액션을 조합한다. 전송·JSON 해석은 Client가 담당한다. 의존성 수만으로 화면 상태를 쪼개지 않는다. |
| `BookDetailView.swift` | 화면·시트·지도 및 표시 영역을 조합한다. 연관 도서 UI가 아직 연결되지 않은 것은 디자인 대기 의도다. 사용자 기존 주석 변경까지 보존했다. |

## 새로 분리한 책임

| 구성 요소 | 소유하는 책임 |
| --- | --- |
| `PrimoBookMapper` | 일반 검색의 Primo JSON → Book 변환, 연도·출판사·저자·표지·소장 위치 해석 |
| `PrimoRecommendationMapper` | 첫 추천 후보·맞춤 추천 제목/후보 변환. 서로 다른 필수 필드 계약을 내부 DTO로 보존 |
| `RecommendationCoverResolver` | 정보나루 표지 주소 조회, HTTP 이미지 상태·MIME·최소 크기 확인 |
| `RecommendationCoverSelector` | 추천 방식별 표지 선정 정책, 병렬 배치 상한, 응답 완료 순서와 무관한 후보 순서 유지 |
| `PrimoAPIClient.searchData` | 추천용 조회의 성공 본문 반환과 HTTP 실패 상태 처리 |
| `Data4LibraryAPIClient.coverURL` | 정보나루 상세 응답에서 표지 주소 추출, HTTPS 보정 |
| `RecommendationClientError` | 두 추천 Client의 공통 입력·설정 오류. 맞춤 추천이 첫 추천 서비스의 오류 타입을 참조하지 않도록 함 |

전송 경로는 기존처럼 기능 Client → 제공자 API → HTTPClient → URLSession이다.
새 파일은 기존 Clients/Book/Client 안에 추가했다. 기존 파일의 폴더 위치를 옮기지 않았다.

## 보존한 동작

- 일반 검색: 빈 응답은 빈 목록, 문서가 있으나 유효한 책이 없으면 기존 Client 오류. 첫 유효 레코드의 순서·식별자·소장 위치와 서지 정규화를 보존한다.
- 첫 추천: 관심 분류·게스트 조회 범위·무작위 페이지·첫 페이지 재사용·후보 중복 제거·추가 페이지 상한을 유지한다. 확인 중인 페이지에서는 정보나루 표지를 우선한 뒤 부족한 수를 Primo 이미지로 채운다.
- 맞춤 추천: 모델 키워드/순위와 실패 시 대체 규칙·관심 분류 우선순위를 유지한다. 후보별 정보나루 → Primo 순서로 표지를 확인하면서 후보 순위를 보존한다.
- 표지는 기존처럼 10권 단위로 확인하고 최대 6권을 반환한다. 요청 수·캐시 정책을 바꾸거나 실측 성능 향상을 주장하는 변경은 아니다.
- Feature에서 사용하는 search/fetch 인터페이스, 공통 Book 모델, 즐겨찾기 저장 키·JSON 형식은 유지한다.
- 연관 도서 자동 조회와 대기 중인 화면 코드는 유지한다. 다른 담당자의 Home·검색·온보딩·캐시·지도 코드는 변경하지 않았다.
- 온보딩 관심사 대신 임시 관심사를 전달하는 기존 연결과 학과 인기 도서의 임시 랜덤 구현은 별도 기능 개선 항목으로 남아 있다.

## 검증

- iOS 27.2 시뮬레이터에서 앱·테스트 빌드 및 **195개 / 37개 suite** 통과. 검색 변환, 추천 정책·전체 흐름, 즐겨찾기 저장·화면 간 연동을 포함한다.
- Foundation 소스 사본의 Swift 6 테스트 **25개 / 5개 suite** 통과. 모든 사본이 현재 제품 소스와 일치함을 확인했다. 일부 테스트는 iOS 실행과 중복되므로 합산하지 않는다.
- 추가로 첫 추천의 페이지 재사용·조회 상한·후보 중복 제거, 맞춤 추천의 표지 출처별 순위 유지, 검색의 빈 결과·전부 무효인 결과·중복 레코드 순서를 검증했다. 기존 추천 기대 결과는 유지했다.
- Swift 문법 검사와 `git diff --check` 통과.
- 기존 `date.now` 의존성 문제로 `BookBasketTests`, `BookDetailFeatureTests` suite를 제외했다. 기존 MainActor/Equatable 컴파일 문제의 `BookBasketIsolationTests.swift`도 빌드에서 제외했다. 전체 테스트 무제외 통과를 의미하지 않는다.
- 현재 Xcode SDK와 SwiftSyntax 사전 빌드 모듈 불일치는 검증 중에만 사전 빌드를 끄고 우회했다. 실행이 끝난 뒤 기존 Xcode 설정을 복원했다.
- 이번 로직 분리 검증은 주입한 조회·전송기와 로컬 테스트로 수행했다. 실서버 호출이나 Postman HTTP 시뮬레이션을 추가 실행하지 않았다. 이전 네트워크 분리의 검증 결과는 [BookNetworking.md](BookNetworking.md)를 참조한다.

## 검토 기록

```text
검토한 commit: 3c463b5dc46359601714e022003cd337149e3175 기반 커밋 전 작업 트리
비교 대상: dev / aae6f8d831a943877c1f7cbd0cfee530a57b0778 (누적 변경), HEAD 3c463b5 (이번 책임 분리)
영향도: L
변경 목적: 담당 도서 코드의 책임을 분리하고 BookFavoritesClient의 미사용 코드 여부를 확인한다.
영향 범위: 이번 변경은 검색 응답 변환·첫 추천·맞춤 추천·관련 제공자 경계. 누적 브랜치에는 검색·상세·추천·소장·표지의 공통 HTTP 분리도 포함된다.
판정 근거: 이번 재구성 단독은 M 범위이나, 브랜치 전체에는 여러 도서 기능이 공유하는 새 HTTP 전송 경계가 있어 L을 유지한다.
확인하지 못한 사항: 실서버·실제 Release 프록시 운영, 기존 테스트 문제로 제외한 범위, 필수 CI 상태
AI 리뷰 결과: needs_human_review
필수 수정 사항: 이번 책임 분리에서 발견된 필수 수정 사항 없음. 기존 테스트 문제와 최종 필수 검증 기준 확인이 필요하다.
검증 근거: iOS 195개/37 suite, Foundation 소스 사본 25개/5 suite, 문법 검사, git diff --check, 호출 지점 및 기존 변환·선정 규칙 비교
AI 승인: not_applicable
사람 코드리뷰: pending
사람 승인: pending
사람 리뷰·승인 근거: 커밋 전 작업 트리이며 아직 PR·사람 리뷰 없음
merge 경로: human_merge
merge 조건 판정: blocked
자동 merge 판정: blocked
판정 이유: 누적 L 변경으로 사람 리뷰·승인이 필요하고, 기존 테스트 및 필수 CI 확인이 남아 있다. 이번 변경의 commit·push·merge는 수행하지 않았다.
```
