# 포스텍 도서관 지도 연결

Refs #52. 기본 지도는 `IndoorMaps/POSTECHLibrary/IMDFData`의 실제 도서관 IMDF다.
기존 C5는 원본·길찾기 회귀 검증용으로 보관하며 앱 기본 지도와 경로 자료에 섞지 않는다.

## 전달받은 자료

- 원본 폴더: `POSTECH Taejoon Park Digital Library IMDF  261026_1631`.
- 원본 생성 시각: `2026-10-26T06:39:35Z`, 생성 도구: IM-DFrnt, IMDF 형식: 1.0.0.
- 10개 파일을 내용 변경 없이 포함하고 `source.json`에 파일별 SHA-256을 기록했다.
- 층은 ordinal 0~4와 표시 이름 1~5층이다. ordinal을 화면 층 번호로 다시 해석하지 않는다.
- unit 273개, fixture 1,650개, opening 254개, section 2개, footprint 2개를 포함한다.
- `amenity.geojson`, 길찾기 노드·연결, 서가 도착 지점·매핑은 전달받지 않았다.

fixture의 서가·가구 도형은 제공된 모양과 층 참조로 표시한다. 모든 fixture를 도서 목적지로
간주하거나 시설 이름에서 서가 키를 추측하지 않는다. 책과 서가의 연결 계약은 #53에서 다룬다.

## 앱 연결

`IndoorMapClient.liveValue`가 `BundledIndoorMapLoader.loadLibrary()`를 호출한다.
파일 I/O·디코딩·DTO 검증은 기존처럼 MainActor 밖에서 실행한다. C5 전용 UUID 호환 정책은
도서관 자료에 적용하지 않는다. 원본의 MultiPolygon·내부 ring·UUID와 층 연결을 유지한다.

선택 파일인 amenity·section은 없으면 해당 요소가 없는 지도로 읽는다. 파일이 존재하면
JSON·FeatureCollection·UUID·층 참조·geometry를 검사한다. 손상된 파일을 누락으로 취급하지 않는다.
address·building은 원본으로 보관하고, section은 층별 구역으로 표시한다.

MapKit은 기존 평면 표시와 층 선택·현재 위치 포커싱을 사용한다. 지도 로딩 실패 시 실제
실패 내용을 표시하고 재시도할 수 있다. 현재 위치 공급은 기존 기능을 유지하며 실제 측위 개발은
이번 작업에 포함하지 않는다.

## 길찾기 자료 준비 전

사용자 확인에 따라 길찾기 노드·서가 자료는 동료가 추후 전달한다. 도서관 navigation 진입점은
`POSTECHLibrary`에서 자료를 확인한다. 자료가 없으면 준비 중 상태를 표시하며 지도와 층 선택은
계속 사용할 수 있다. C5 navigation으로 자동 대체하지 않는다.

노드 자료 수령 후 같은 #52 작업에서 내보내기 형식·지도 개정·층 참조·서가 도착 지점을 확인하고
연결해야 한다. 현재 C5 데이터셋용 `dataset.json` 계약을 새 export에 그대로 적용할 수 있다고
확정하지 않는다. 형식이 다르면 해당 계약을 검토해 같은 브랜치에서 연결한다.

지도 표시 검증만으로 #52 전체를 완료 처리하지 않는다. 아직 준비되지 않은 노드·서가 데이터
연결 검증과 팀의 화면 확인이 남아 있다.

## 시뮬레이터 확인

`IndoorPositioningSimulator`에서도 같은 `POSTECHLibrary/IMDFData` 폴더 또는 전달받은 원본 폴더를 연다.
Debug iOS Simulator에서 `groundTruth` 위치 공급을 사용한다. C5 도면을 그대로 연 채 보낸 위치는
새 도서관의 층·경계 검사를 통과하지 못할 수 있다. 표시되는 3층의 IMDF ordinal은 2다.

길찾기 노드가 없어도 지도 표시·층 선택·시뮬레이션 위치 표시를 검증할 수 있다. 실제 Core Location
실내 위치 품질, 실제 기기 측위, 블루닷 보정의 검증 결과로 해석하지 않는다.

## 자동 검증

`LibraryIndoorMapTests`에서 기본 지도 선택·원본 10개 파일의 해시·층과 요소 개수·층 참조를 확인한다.
`LibraryMapFeatureTests`는 길찾기 자료가 준비되지 않았을 때 지도 최초 표시와 층 선택을 검증한다.
`IndoorMapInitialLayoutTests`는 실제 도서관의 1~5층을 MapKit에 연결해 도형 표시와 평면 카메라 적용을 확인한다.
기존 C5 로더·길찾기 테스트도 함께 유지한다.

선택 파일 누락과 손상, section의 잘못된 층 참조는 합성 GeoJSON으로 검증한다.
