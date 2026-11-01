# 길안내 진행에 따른 지도 포커스와 확대

기존 `postech-library/fingerprint-library.xcodeproj`에서 빌드한다. 길안내에서 검증한 현재 위치와 진행도를 사용해 카메라를 갱신한다. 먼 뒤쪽 통로가 지도 범위를 고정하지 않도록 현재 위치와 다음 안내 구간을 중심으로 보여 준다.

## 동작

- 다음 안내 지점과 회전 뒤 8m를 포함하되, 앞쪽 표시 경로는 최대 30m로 제한한다.
- 안내 구간이 바뀌면 이동 거리가 2m보다 작아도 즉시 카메라를 갱신한다.
- 같은 구간에서 앞으로 2m 또는 뒤로 5m 이동하면 범위를 다시 계산한다. 작은 위치 흔들림에는 유지한다.
- 서가가 표시 범위에 들어오면 목적지도 함께 보여 준다. 최소 표시 폭은 `max(12m, 위치 오차 × 2 + 8m)`다.
- 사용자와 표시 경로가 안내 UI에 가리지 않도록 실제 지도 크기와 상하 여백을 반영한다. 회전 각도는 유지한다.
- 지도를 손으로 움직이면 자동 추적을 멈춘다. 현재 위치 버튼으로 다시 시작한다.
- 위치가 유효하지 않으면 카메라를 유지한다. 도착 화면에서는 중단하고, 다음 책으로 진행하면 추적 기준을 초기화한다.
- 자동 확대는 목적지 층에서, 남은 경로에 다른 층 이동이 없는 경우 적용한다.

위 거리와 표시 폭은 구현 기본값이다. 실제 보행과 디자인 확인을 거쳐 조정할 수 있다.

## 코드

| 파일 | 역할 |
| --- | --- |
| `BookNavigationCameraTracking.swift` | 진행도에서 표시할 구간과 갱신 시점 계산 |
| `BookNavigationCameraFitter.swift` | 실제 지도 크기·회전·안내 UI 여백에 맞는 카메라 계산 |
| `BookNavigationFeature.swift` | 위치·진행도·수동 조작·현재 위치 버튼·다음 책을 카메라 요청에 연결 |
| `BookNavigationView.swift` | 카메라 요청과 지도 조작 콜백 전달 |
| `IndoorMapKitView.swift` | 배치 후 카메라 요청을 적용하고 사용자 지도 조작 감지 |
| `IndoorMapFeature.swift` | 안내용 카메라 요청 값 추가 |

기존 일반 지도 요청과 도서·네트워크 계약은 유지한다. Xcode의 폴더 자동 동기화를 사용하므로 새 소스를 프로젝트 파일에 수동 등록할 필요가 없다.

## 기존 위치 시뮬레이터 연결

연결은 `c147af0`에서 이미 추가되어 dev에 포함돼 있다. 이번 변경은 기존 위치 스트림을 사용하며 연결 코드를 추가하거나 바꾸지 않는다.

- [IndoorLocationClient.swift](../fingerprint-library/Clients/Location/IndoorLocationClient.swift): Debug iOS Simulator에서 기본으로 합성 위치를 선택한다. `INDOOR_POSITION_SOURCE=live`이면 실제 위치 공급으로 전환한다.
- [IndoorSimulationLocationProvider.swift](../fingerprint-library/Clients/Location/Simulation/IndoorSimulationLocationProvider.swift): `127.0.0.1:57575`에 연결하고, 끊어지면 다시 연결한다.
- [IndoorSimulationFrame.swift](../fingerprint-library/Clients/Location/Simulation/IndoorSimulationFrame.swift): 전송된 위치와 층을 읽는다. Mac 시뮬레이터의 ‘Wi-Fi 위치 기반 측위’를 꺼 `groundTruth` 모드로 사용한다.
- 시뮬레이터에도 앱과 같은 도서관 도면을 등록하고 같은 층에서 확인한다. Release와 실제 iPhone에는 이 연결을 사용하지 않는다.

## 검증 범위와 제한

실행한 결과와 검토 commit은 PR 본문·검토 기록에 남긴다.

- 실제 `BookNavigationView`에 50Hz 위치 스트림을 전달해 안내 단계와 지도 중심·확대 범위가 함께 바뀌는지 확인한다. 짧은 경로와 먼 뒤쪽 통로가 있는 경로를 각각 사용한다.
- 세로·가로 화면, 회전 유지, 구간 전환, 작은 위치 흔들림, 수동 중단·재개, 다음 책 전환을 검사한다.
- 최신 dev의 `DatasetRecommendationTests.swift:116`, `OnboardingFeatureTests.swift:37`가 현재 Xcode에서 실행 준비 단계의 오류를 내므로, 이번 지도 검사는 Git에서 제외되는 임시 지도 전용 실행 설정으로 수행한다. 두 테스트 파일과 공유 실행 설정은 수정하지 않는다. 앱 전체 검사 통과로 취급하지 않는다.
- `IndoorLocationAuthorizationMonitorTests.queriesServicesOutsideMainThread`는 이전 dev 검증에서도 재현한 실패다.
- 기존 Vision 글자 인식 대기로 완료하지 못했던 `BookNavigationArrivalScreenTests`, `HomeBookCardScreenTests` 두 묶음은 지도 회귀에서 제외하며 통과로 계산하지 않는다.
- 기존 SwiftSyntax 사전 빌드 호환 문제를 피하려고 검사 중에만 사전 빌드를 끄고 종료 후 원래 설정을 복원한다.
- 실제 도서관 보행과 Mac 시뮬레이터를 직접 조작하는 수동 이동 검증은 완료하지 않았다.

로그:

- 카메라·안내: `/tmp/postech-issue132-dev-camera-tests-20261102.log`
- 지도 회귀: `/tmp/postech-issue132-dev-map-regression-tests-20261102.log`
- 기존 추천 검사 준비 오류: `/tmp/postech-issue132-dev-test-compile-failure-20261102.log`
- 기존 온보딩 검사 준비 오류: `/tmp/postech-issue132-dev-onboarding-test-compile-failure-20261102.log`

기존 사용자의 프로젝트 설정 변경과 책 상세 화면 주석, `Secrets.xcconfig`는 PR에 포함하지 않는다.
