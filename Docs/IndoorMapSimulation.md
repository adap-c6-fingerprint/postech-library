# 실기기 Indoor Sensor Simulator QA

- 앱 브랜치: `qa/device-indoor-simulator`, 최신 `origin/dev`에서 분기.
- Xcode의 `fingerprint-library` scheme을 **Debug / 실제 iPhone**으로 실행한다.
- iPhone과 Mac을 같은 Wi-Fi에 연결하고 위치 권한과 로컬 네트워크 권한을 허용한다.
- Mac에서 앱과 같은 IMDF 지도를 연 뒤 **블루닷 연결 준비**를 누른다. Wi-Fi 위치 기반 측위는 끈다(`groundTruth`).
- 앱의 **홈 탭을 5번 연속** 누른다. 탭 사이 간격이 1초를 넘거나 다른 탭을 누르면 횟수가 초기화된다.
- 연결 화면에서 **연결 / 다시 연결**을 누른다. 주소를 비우면 Bonjour(`_indoor-sim._tcp`)로 Mac을 찾는다. 직접 연결하려면 Mac의 IP와 포트(기본 `57575`)를 입력한다.
- 연결 화면에서 **실제 위치로 전환**할 수 있다. 설정은 Debug 앱에 저장된다.

## 센서 역할

Mac 프레임에서 좌표와 층만 읽는다. 시뮬레이터가 보낸 `headingDegrees`는 디코딩하지 않는다.
실기기 Core Location의 나침반을 별도로 구독해 지도 방향에 적용한다. 진북을 얻을 수 없으면 기기의 자북을 사용한다.
기기 GPS·층과 기압계 층 보정이 시뮬레이터 좌표·층을 덮지 않는다. 나침반 이벤트도 좌표 측정 시각을 갱신하지 않는다.
위치 권한이 거부됐거나 나침반을 사용할 수 없으면 방향은 표시하지 않지만 Mac 위치 수신은 유지된다.

## Mac의 층 변경

층 목록, `⌘1`~`⌘9`, 계단·엘리베이터의 위층/아래층 이동은 현재 위도·경도를 유지하고 층만 변경한다.
열린 지도에 없는 층의 단축키는 비활성화된다. 위층/아래층 버튼의 수직 연결 시설 제한은 유지된다.

## 배포 분리

연결 UI·홈 5회 탭·TCP/Bonjour·연결 설정·실기기 나침반 합성은 모두 `#if DEBUG`로 감싼다.
Debug만 `Configuration/Info-Debug.plist`의 로컬 네트워크 설명과 Bonjour 선언을 사용한다.
Release는 원래 `fingerprint-library/Info.plist`와 실제 Core Location 공급자만 사용한다.

## 실기기 확인 순서

1. 홈 5회 탭으로 연결 화면이 열리고 Mac 위치 수신 중으로 바뀌는지 확인한다.
2. Mac에서 블루도트를 이동하면 iPhone의 좌표가 따라오는지 확인한다.
3. `⌘3` → `⌘4` → `⌘3`으로 이동할 때 좌표가 유지되고 층만 바뀌는지 확인한다.
4. Mac의 방향만 바꿀 때 iPhone 방향이 변하지 않고, iPhone을 회전할 때 지도 방향이 변하는지 확인한다.
5. Mac 연결 종료·재시작, 앱 백그라운드 복귀, 실제 위치 전환 후 재연결을 확인한다.

연결 설정은 기존 개발용 시스템 시트를 복원했다. 닫기와 스와이프 종료를 제공하고 안내 화면과 동시에 표시하지 않는다. 참고: [Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).
