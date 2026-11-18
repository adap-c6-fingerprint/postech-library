# 오프라인 시연(Demo) 빌드

와이파이 없이 "이런 식으로 동작한다"를 보여주기 위한 시연용 빌드다. 운영 서비스용이 아니다.

## 구성

| 항목 | 값 |
|---|---|
| Scheme | `fingerprint-library-demo` (Run·Profile·Archive = `Demo` 구성) |
| 번들 ID | `com.youngmin.fingerprint-library.demo` (기존 앱과 같이 설치 가능) |
| 표시 이름 | `Po:book 데모` |
| 컴파일 조건 | `DEMO` |
| 중계 토큰 | 넣지 않는다(`Demo` 구성에서 빈 값). 빌드 검사 스크립트가 토큰이 들어가면 실패시킨다. |
| Firebase | `GoogleService-Info.plist`의 번들 ID와 달라 초기화를 건너뛴다. |

## 동작

- `HTTPClient.liveValue`가 `DEMO`에서 `HTTPClient.demoReplay()`가 되어, 번들의 `Resources/DemoFixtures`에 녹화한 응답만 돌려준다. 네트워크로 나가지 않는다.
- 녹화하지 않은 요청은 `DemoFixtureMissError`("오프라인 시연 버전에 포함되지 않은 정보예요.")로 실패한다.
- 녹화하지 않은 검색어와 소장 정보는 번들 `RecommendationDataset.json`(812권)에서 찾는다.
  - 데이터셋에는 대출 상태가 없어 "대출 상태 확인 필요"로 표시된다.
  - 녹화하지 않은 책은 기본 표지로 나온다.
- 지도·서가·길찾기 그래프는 원래 번들 데이터라 그대로 동작한다.
- `DemoFixtures` 폴더는 Debug·Release 구성에서 `EXCLUDED_SOURCE_FILE_NAMES`로 제외되어 운영 앱에는 들어가지 않는다.

## 녹화된 검색어 (전체 탭)

프로그래밍, UI, UX, 디자인, 코딩, 개발, 문학, 스티브잡스

각 검색어마다 결과 책의 표지, 책등, 책 소개(Yes24), 소장 정보를 녹화했다. 추천 탭이 쓰는 데이터셋 812권도 같은 방식으로 표지, 책등, 책 소개, 소장 정보를 모두 녹화했다(`POBOOK_DEMO_RECORD_DATASET_COVERS=1`). 녹화 묶음은 대부분 표지 이미지다.

대출 상태는 녹화한 날(2026-11-18) 기준 값이다. 시연 중 실제 대출 상태와 다를 수 있다.

## 다시 녹화하기 (Debug, 시뮬레이터)

1. `fingerprint-library` scheme을 Debug로 빌드해 시뮬레이터에 설치한다.
2. 녹화 폴더와 검색어를 환경 변수로 주고 실행한다. 앱이 같은 Client로 요청을 보내며 성공 응답을 폴더에 저장한다(인증 헤더는 저장하지 않는다).

```bash
SIMCTL_CHILD_POBOOK_DEMO_RECORD_DIR=/tmp/pobook-demo SIMCTL_CHILD_POBOOK_DEMO_RECORD_QUERIES='프로그래밍|UI|UX' xcrun simctl launch --terminate-running-process <simulator-id> com.youngmin.fingerprint-library
```

3. 진행 상황은 `DemoFixtureWarmup` 로그 카테고리의 `demo fixture warmup finished`로 확인한다. 녹화 모드에서 앱 화면을 직접 조작하면 그 요청도 함께 저장된다.
4. 폴더 내용을 `fingerprint-library/Resources/DemoFixtures/`로 복사하고 Demo scheme으로 다시 빌드한다.

## 한계

- 실내 측위는 녹화로 대체되지 않는다. 비행기 모드에서 실기기 측위가 되는지 시연 전에 확인해야 한다.
- 지도 배경(Apple 지도 타일), 외부 링크(Yes24 원문, 개인정보처리방침)는 오프라인에서 열리지 않는다.
