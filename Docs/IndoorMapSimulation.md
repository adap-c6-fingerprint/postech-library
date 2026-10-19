# C5 가상 서가와 시뮬레이터 위치

Refs #5. 실제 Blue Dot 측위·보정과 C5 현장 측위 검증은 마지막 단계로 미룬다.
사용자 수동 출발점 지정은 채택이 확정되지 않아 보류한다. 이 문서는 #5의 테스트 위치 공급 범위를
설명하며 실제 측위 완료를 뜻하지 않는다. #7의 [단일 서가 길찾기와 경로 설정](IndoorRouting.md)은 구현했다.

## 실행

1. `2026-c6-pre-fingerprint/IndoorPositioningSimulator`에서 Indoor Sensor Simulator를 실행한다.
2. 앱 번들의 `Resources/IndoorMaps/C5/IMDFData`와 같은 도면을 연다.
3. **Wi-Fi 위치 기반 측위**를 끈다. `groundTruth` 모드의 정확한 가상 좌표·층을 사용한다.
4. postech-library를 **Debug iOS Simulator**로 실행한다. 기본으로 로컬 시뮬레이터에 연결한다.
5. Mac 시뮬레이터에서 방향키로 이동하고 계단·엘리베이터 영역에서 층을 바꾼다.
   앱의 파란 점이 같은 좌표·층을 반영한다. 층이 바뀔 때 지도도 해당 층으로 이동한다.
   같은 층에서 사용자가 다른 층의 지도를 조회하는 동작은 계속 허용한다.
6. 서가 핀을 누르면 가상 서가 이름을 확인한다. **경로 보기**를 누르면 경로 설정 화면으로 이동해
   현재 위치에서 해당 서가까지의 경로를 계산한다.

연결 대기·수신 오류 문구는 지도 위쪽 현재 위치 버튼 아래에 표시한다. 새 구독의 초기 연결 대기에는
현재 위치를 비우고 완료된 경로 미리보기는 유지한다. 실제 연결 단절이나 5초 수신 timeout은
위치·경로를 무효화하고 1초 간격으로 재연결한다. 새 위치 수신까지 이전 점을 실제 현재 위치로 유지하지 않는다.
앱 비활성화 시 위치 연결·진행 중 탐색을 취소하며 완료된 경로는 유지한다. 홈과 경로 설정 사이
push/pop은 위치 구독을 유지하고, 경로 설정에서 뒤로가면 경로를 닫는다.

실제 Core Location 경로가 필요할 때만 실행 환경 변수 `INDOOR_POSITION_SOURCE=live`를
설정한다. Release·실제 기기에는 TCP 위치 공급 코드를 포함하지 않는다. 가상 위치는
`IndoorPosition.Source.simulation`으로 전달하며, MapKit 기본 `MKUserLocation`과 겹쳐 표시하지 않는다.
표시용 정확도 0은 가상 좌표를 그대로 사용한다는 뜻이며 실제 측위 정확도 보장이 아니다.

## 위치 전송 계약

기존 시뮬레이터의 `SimulationTransport.swift`·`SensorSimulation.swift`·`Geometry.swift`를 기준으로 한다.
시뮬레이터 코드나 사용자 로컬 경로를 Xcode 패키지 의존성으로 추가하지 않는다.
앱의 위치 어댑터가 기존 전송 형식 중 필요한 필드를 읽으며 센서 원시값은 사용하지 않는다.

- 주소: `127.0.0.1:57575`, TCP. HTTP 인터페이스가 아니다.
- 경계: 4바이트 big-endian body 길이 + UTF-8 JSON. 분할 수신·한 번에 여러 프레임 수신을 지원한다.
- 최대 body 길이: 앱에서 1 MiB. 0 또는 이를 넘는 길이는 연결을 다시 시도한다.
- `schemaVersion`: 1.
- `sessionID`: UUID. `sequenceNumber`: UInt64. 같은 연결·세션의 중복/역순 프레임은 무시한다.
- `generatedAt`: producer의 기본 JSONEncoder Date 표현인 2001-01-01 기준 초.
- `positioningMode`: `groundTruth`만 수용한다. `radioBased`·필드 누락은 모드 전환 안내를 표시한다.
- `device.position.coordinate`: `latitude`·`longitude`, WGS84.
- `device.position.levelOrdinal`: IMDF ordinal. 화면에서 조회 중인 층으로 대체하지 않는다.
- 위치는 기존 유효성·시각 정책과 로드된 도면의 층/경계로 검증한다. 서로 다른 도면의
  동일 ordinal만으로 같은 데이터셋임을 인증하지는 않는다. 양쪽에서 같은 C5 도면을 열어야 한다.

## 가상 서가

`shelves.json`의 기존 `mock-01`~`mock-03`을 가상 서가로 표시한다. 키·원래 도형 참조·
도착 노드·층은 유지한다. 이 구역은 실제 도서관 서가가 아니며 원본 C5 IMDF를 수정하지 않는다.

핀의 좌표는 연결된 **도착 노드의 좌표**다. 서가의 물리적 중심이나 서가 도형을 뜻하지 않는다.
탐색기는 annotation의 좌표나 시설 이름에서 목적지를 추측하지 않고
`ShelfKey → ShelfDestination.arrivalNodeID`로 목적지를 조회한다.
핀 선택은 TCA `selectedShelfKey`에 반영하며 다른 층·등록되지 않은 키는 선택하지 않는다.
실제 도서→서가 계약은 #6에서 도서 담당과 합의한다.

## 이슈 완료 판단

#5는 이번 범위의 코드 검증·시뮬레이터 통합 확인과 팀 리뷰가 끝나기 전까지 유지한다.
기존 이슈 본문의 실제 측위·수동 출발점·홈 추천 연결 항목은 최신 범위에 맞게 재정리해야 한다.
측위는 별도 후속 범위, 수동 출발점은 보류, 홈·도서 연결은 #6 협업 범위로 구분한다.
이 문서가 GitHub 이슈 본문을 자동 변경하거나 해당 작업의 완료를 뜻하지는 않는다.

## #5 최초 변경의 검증

아래 수치는 시뮬레이터 최초 이식 시점의 근거다. 이후 #7 누적 검증은 [길찾기 문서](IndoorRouting.md)에 기록한다.

- Swift Testing 54개 함수·102회 실행: 실패·skip·런타임 경고 0.
- 실제 iOS Simulator TCP 연결로 분할 수신, 중복/역순 무시, 단절·새 세션 재연결, 취소를 검증했다.
- producer의 `SimulationSessionServer`·`SimulatedSensorGenerator`와 앱의 수신 코드를 임시 macOS
  검증 프로그램에서 연결해 `groundTruth` 위치 25개와 ordinal 4→0 전환을 확인했다.
  플랫폼 조건부 컴파일의 바깥 가드만 검증 프로그램에서 해제했으며 수신 구현은 동일하다.
- 시뮬레이터의 기존 `IMDFArchiveLoader`가 번들 원본 C5의 6개 층을 읽는 것을 확인했다.
- Python 가져오기 회귀 검사 6개와 Release 빌드가 통과했다. Release 실행 파일의
  시뮬레이터 provider 심볼이 0개인 것도 확인했다.
- UI 자동화 도구가 시작되지 않아 Mac 시뮬레이터 창을 직접 조작하는 전체 시연은 확인하지 못했다.
  실제 기기 측위 검증과 구분하며, 팀의 수동 조작 QA·코드리뷰는 남아 있다.
