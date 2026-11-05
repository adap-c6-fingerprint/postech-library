# PLI-268 — Microsoft Clarity

## 연결

- Mobile Apps 프로젝트 ID: `z8n14vbcvp`.
- SPM 제품 `Clarity`, 버전 `4.1.2` 고정. main 자동 업데이트는 사용하지 않는다.
- 공식 4.1.2 릴리스에는 Xcode 26.x 호환성 수정이 포함되어 있다.
- Firebase·TCA의 기존 잠금 버전은 유지한다. Clarity에는 별도 plist가 필요하지 않으며 Firebase plist의 Git 제외 정책도 그대로다.
- SwiftUI AppView의 활성 상태를 SessionReplayRuntime에 전달한다. Firebase 설정 파일 유무와 무관하게 동작하며, 별도 AppDelegate나 @main은 추가하지 않는다.

## 동의

최초 실행 및 마이페이지 → 데이터 수집 설정에서 **화면 이용 녹화 허용**을 별도로 고른다.
GA 사용 분석·오류 진단을 허용했다고 화면 녹화를 자동 허용하지 않는다.
기존 사용자는 Firebase 동의를 유지한 상태로 새 녹화 항목을 한 번 선택한다.

SessionReplayConsent는 `pobook.clarity.consent.v1`에 저장한다. 기본값은 꺼짐이다.
동의·앱 활성·보호 화면 없음 조건이 모두 충족된 뒤에만 SDK를 초기화한다.
SDK 준비 callback도 현재 조건을 다시 검사한다. 준비 중 철회하거나 보호 화면에 진입했다면 재개하지 않는다.
철회하면 pause와 consent(false)를 적용한다. 백그라운드 및 보호 화면은 일시 pause하고 조건이 회복되면 resume한다.
이미 동의하에 수집된 대기 데이터/서버 기록의 즉시 삭제 기능은 이번에 구현하지 않았다. pause를 서버 데이터 삭제로 해석하면 안 된다.

## 첫 연결의 보수적인 보호 범위

- 앱 루트와 기존 analyticsScreen 적용 화면에 clarityMask를 적용한다. 텍스트·이미지의 내용보다 배치·탭·스크롤 흐름을 보는 초기 연결이다.
- 검색 탭, 온보딩, 마이페이지, 학과 편집, 수집 설정, 시뮬레이션 설정은 보호 modifier로 녹화를 일시 중지한다.
- 보호 화면이 중첩되면 마지막 화면이 닫힐 때까지 멈춘다. 검색 탭 전체를 보호하므로 그 탭에서 여는 상세·장바구니도 함께 중지될 수 있다.
- MapKit 공통 뷰를 maskView로 가린다. 지도에 그려지는 현재 위치와 경로를 무방비로 녹화하지 않기 위한 조치다. 좌표·층 번호를 별도 태그로 보내지 않는다.
- 학과/관심사 원문, 검색어, Firebase 사용자 ID, 실제 사용자 식별자를 Clarity custom tag/user ID로 추가하지 않는다. SDK 자체의 기기·세션 메타데이터와 임의 식별자는 별도다.
- Clarity는 OS의 화면 동영상 파일을 저장하는 기능이 아니라 화면/상호작용을 재구성하는 session replay다.

코드의 mask 적용만으로 실제 replay에서 민감 정보가 완전히 가려졌다고 확정하지 않는다.
**배포 전에 콘솔 Settings → Masking을 Strict로 설정하고, 실기기 replay에서 검색어·프로필·지도·위치 표시가 없는지 확인해야 한다.**
콘솔 masking은 관리자 권한이 필요하다. 녹화를 보는 것이 목적이라고 전체 앱을 무분별하게 unmask하지 않는다.

## 빌드 구분

Clarity 세션 callback에서는 `build_channel` 태그를 대기 상태로 둔다.
동의·앱 활성·보호 화면 없음 조건과 SDK 동의 적용이 모두 충족되면 태그를 설정한다.
보호 화면이나 비활성 상태에서 callback이 와도 조건 회복 후 설정하며, SDK가 실패를 반환하면 다음 허용된 상태 적용에서 재시도한다.
성공한 태그는 같은 세션에서 반복 설정하지 않는다. 태그 실패만으로 녹화를 차단하지는 않는다.

- simulator: 시뮬레이터
- development: Debug 실기기
- release: Release 빌드. TestFlight와 App Store를 따로 구분하지 않는다.

GA의 build_environment와 별도이며, Firebase/GA와 Clarity 세션을 사용자 ID로 직접 연결하는 기능은 이번 범위에 없다.

## 직접 확인할 순서

1. Clarity 프로젝트가 Mobile Apps / iOS용인지, 프로젝트 ID가 맞는지 확인한다.
2. 콘솔 Masking을 Strict로 설정하고, 기존 Xcode 매크로 승인을 마친 환경에서 패키지를 resolve한 뒤 빌드한다.
3. 앱에서 모두 거부: SDK 초기화가 없고, 검색·도서·지도 이용이 계속 가능해야 한다.
4. 마이페이지에서 화면 이용 녹화만 허용하고 저장한다. 마이페이지를 닫아 추천 탭 등 일반 화면으로 나간다.
5. 추천 목록을 스크롤하고 도서를 연다. 검색/프로필/설정 진입 시에는 녹화가 멈춰야 한다.
6. 앱 비활성/활성, 보호 화면 중첩, 녹화 철회 및 재실행을 확인한다.
7. Wi-Fi와 콘솔의 데이터 수집 규칙을 확인한다. 전체 세션 반영에는 최대 약 2시간이 걸릴 수 있다.
8. Recordings에서 build_channel로 테스트 세션을 찾고, 텍스트·이미지와 지도 영역 가림을 실제로 검수한다.
9. SDK를 포함한 실제 수집 내용에 맞춰 개인정보 안내·App Store 공개 내용·보관 기간·접근 권한을 담당자가 검토한다.

## 검증

```sh
python3 -m unittest discover -s Scripts/tests -p test_clarity_setup.py -v
```

이 검사는 SDK 고정 버전과 앱 링크, Firebase·TCA의 고정 버전, 보호 modifier 연결을 검사한다.
동시에 네트워크가 없는 SDK 대역으로 **실제 SessionReplayRuntime**을 컴파일해 동의 전 미초기화·비동기 준비 중 보호 화면 진입·중첩 보호·백그라운드·철회 후 늦은 callback·재실행 복원을 실행한다.
태그 지연 적용·동의 → 태그 → 재개 순서·설정 실패 후 재시도·성공 후 중복 방지·SDK 동의 실패 중 태그 차단도 검사한다.
실제 SDK 바이너리의 수집 결과나 콘솔 수신을 대신하는 검사는 아니다.

### 2026-11-05 검증 결과

- Clarity 전용 검사 4개 통과. SDK 대역을 사용한 실제 Runtime의 실행 검사도 포함한다.
- Clarity 4.1.2 다운로드·체크섬 확인·패키지 해결 완료. 기존 Package.resolved의 다른 pin 변경은 남기지 않았다.
- 실제 Clarity 바이너리 및 Firebase 헤더로 Runtime·수집 설정·공통 modifier의 Simulator Debug / 실기기 Release 독립 타입 검사 통과. 앱 전체 링크 검증과는 다르다.
- 전체 Python 검사 41개 중 38개 통과, 3개 실패/오류. 이 3개는 기존 Firebase 검사에서 dev의 OTHER_LDFLAGS·shellScript 배열 표현을 문자열로 가정하는 문제다. dev 원본에도 같은 배열 값이 있음을 확인했으며 이번 작업에서 무관한 설정/검사 정리는 하지 않았다.
- 전체 앱 빌드는 기존 TCA 등 매크로 사용 승인 요구로 ComputeTargetDependencyGraph에서 중단됐다. 승인을 우회하지 않았다.
- 실제 Clarity 프로젝트 수신·마스킹 결과·앱 화면 회귀·Archive는 미확인이다. 셀프 검사만으로 운영 배포 가능한 상태라고 판정하지 않는다.

## 공식 참고

- [iOS 설치와 API](https://learn.microsoft.com/en-us/clarity/mobile-sdk/ios-sdk)
- [4.1.2 릴리스](https://github.com/microsoft/clarity-apps/releases/tag/4.1.2)
- [Mobile masking](https://learn.microsoft.com/en-us/clarity/mobile-sdk/clarity-sdk-masking)
- [Apple App Store 개인정보 안내](https://learn.microsoft.com/en-us/clarity/mobile-sdk/sdk-apple-appstore-privacy-guidance)
