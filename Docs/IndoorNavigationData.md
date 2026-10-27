# 지도·routing·목적지 데이터 묶음

현재 앱의 기본 지도는 [포스텍 도서관 IMDF](LibraryIndoorMap.md)다. 도서관 노드·서가 자료는
추후 전달 예정이며 준비 전에는 지도·층 선택을 유지하고 상태를 표시한다. 아래 C5 데이터셋 계약은
회귀 검증용이며 새 도서관 export 형식이 동일하다고 가정하지 않는다.

Refs #5. #7 탐색기를 붙이기 전에 필요한 데이터 로딩과 목적지 조회를 제공한다.

## 로컬 C5 준비

현재 체크아웃에는 개발용 C5 데이터 묶음이 포함되어 있다. 다음 명령은 원본 프로젝트에서 이를 갱신할 때 사용한다. [사용 범위와 라이선스](IndoorMapData.md)를 먼저 확인한다.

```sh
python3 Scripts/import-c5-local.py
```

기존 13개 IMDF·라이선스를 보존하고, Fingerprint의 현재 working tree에 있는 `Fingerprint/Debug/RoutingGraphTest/Resources/routing-graph.geojson`을 바이트 그대로 복사한다. 두 층 이상에서 destination 노드가 포함된 unit 3개를 결정적으로 골라 `shelves.json`에 시연용 구역으로 연결한다. 가까운 노드나 문자열 유사도로 실제 서가를 추정하지 않는다. 생성한 JSON에서 키·구역·도착점을 검토한다. 이미 수정된 로컬 도면·그래프·목업 매핑은 기본 실행으로 덮어쓰지 않으며, 검토 후 `--replace`로 교체한다.

```text
Resources/IndoorMaps/C5/  (임시 개발용 데이터로 Git 추적)
  IMDFData/             기존 원본과 라이선스
  source.json           13개 원본 해시와 출처
  routing-graph.geojson  원본 그래프
  shelves.json          c5-demo 데이터셋의 목업 목적지
  dataset.json          읽는 지도 파일 8개·그래프·매핑의 SHA-256과 출처
```

layout_version은 그래프의 값을 그대로 쓴다. IMDF manifest.version은 형식 버전이며 지도 개정 번호로 사용하지 않는다. 해시는 가져온 파일이 이후 섞이거나 바뀌는 것을 탐지한다. 두 파일이 동일한 편집 개정에서 export됐음을 인증하거나 실제 보행 가능성을 보장하지는 않는다. 새 도면·그래프·매핑을 함께 검토하고 다시 가져와야 한다.

기준 원본 HEAD는 `ec34f3412694f9afd2bd710302369a4d92cf1201`이며 그래프를 포함한 미커밋 수정이 있다. 실제 재현 기준은 `source.json`·`dataset.json`의 SHA-256과 source_worktree_changes다. 데이터와 `.imdfrnt` 원본을 수정하지 않는다. 사용자 요청으로 데이터 묶음을 Git에 포함하며 동봉된 Apple 라이선스는 보존한다. 공유 범위 확인은 별도이며, PR 설명에 추가 좌표나 캡처를 첨부할 필요는 없다.

## 책임과 검증

- `Domain/Routing`: Fingerprint의 RouteGraph 계약을 참고한 순수 모델이다. 원본 ID·방향·접근성·좌표와 제공된 traversal_seconds를 보존한다.
- `Clients/IndoorRouting`: 파일 해시, DTO·Mapper, 번들 I/O와 TCA 의존성을 담당한다.
- `Domain/IndoorMap/ShelfDirectory`: 데이터셋 내부 키로 도형·층·도착 노드·좌표를 조회한다. Book·API·위치 서비스에 의존하지 않는다.
- `Features/IndoorMap`: 지도 뒤에 navigation 데이터를 읽어 상태에 보관한다. 실패해도 지도·층 선택은 유지한다. 재시도·취소와 오래된 응답 무효화를 제공한다. 현재 화면에는 추가 UI를 표시하지 않는다.

schema 1·명시적인 layout_version·양의 탐색 반경, 전체 Feature ID 유일성, WGS 84 좌표, 노드 층 UUID/ordinal, 연결 끝점·방향·카테고리·접근성을 검사한다. 없는 노드·자기 연결·끝점 불일치·길이 0의 동일 층 연결·accessible 계단·층간 walkway를 거부한다.

도면 바깥 출입구 등은 유효 좌표·층 참조를 확인한 뒤 보존하고 outsideFloorNodeIDs에 남긴다. 고립 노드와 방향·접근성을 적용하지 않은 연결 그룹도 진단한다. 약한 연결 그룹 하나가 특정 방향·이동 수단의 경로 존재를 보장하지 않는다. 장애물·벽과 전체 polyline의 통과 가능성은 검증하지 않는다.

현재 C5는 노드 168개·연결 178개·연결 그룹 1개·고립 노드 0개다. 도면 바깥 출입구 노드 1개와 층간 연결 5개가 진단된다. 원본 그래프에는 층간 실측 거리와 traversal_seconds가 없다. 2026-10-19 사용자 지시에 따라 별도 `cross-floor-distances.json`에 시연용 추정 거리와 근거를 추가했다. 원본 그래프는 보존하며, [계산 기준과 추정값 표시](IndoorRouting.md)를 따른다.

서가 매핑은 schema·데이터셋·layout_version, 중복/빈 키, 지도 요소 종류/ID, 같은 층의 도착 노드와 도착점의 도면 내 위치를 확인한다. `mock`은 시연용 구역이며 C5 unit·fixture가 실제 도서관 서가라는 뜻이 아니다. 노드와 구역 사이 실제 접근 가능성은 현장/도면 검토가 필요하다.

## 후속 기능에서 사용

```swift
let data = try await BundledIndoorNavigationLoader().loadC5(on: map)
let destination = try data.shelves.destination(
    for: ShelfKey(datasetID: "c5-demo", value: "mock-01")
)
// geometry / floorID: 지도 표시용
// arrivalNodeID / arrivalCoordinate: #7 탐색 입력용
```

TCA 화면에서는 store.navigation을 사용한다. `mode: mock`인 목적지는 해당 층에서 가상 서가 핀으로 표시하며 선택한 키는 `selectedShelfKey`에 보관한다. 핀 위치는 기존 도착 노드의 좌표이며 실제 서가 도형의 중심이 아니다. 준비 전/실패는 isLoadingNavigation·navigationLoadError로 구분하며 재시도는 `.retryNavigationTapped`다. 외부 도서의 위치 표시 문자열을 이 키로 해석하지 않는다. 매핑되지 않은 키는 unmappedShelf 오류다. 실제 도서관 소장본·서가 계약은 #6에서 도서 담당과 합의한다.

단일 목적지의 현재 위치 연결·A*·층별 경로 표시는 [#7 구현](IndoorRouting.md)에서 제공한다. 여러 서가의 최단 방문 순서와 실시간 안내는 후속 범위다. 이 변경만으로 #5·#7 전체를 완료 처리하지 않는다.

## 테스트

IndoorNavigationTests는 합성 IMDF·GeoJSON·매핑으로 해시·버전·참조 오류와 진단을 검증한다. IndoorNavigationFeatureTests는 실패 시 지도 유지·재시도·이탈 뒤 늦은 응답 무시·재진입을 확인한다. 실제 C5 번들 검사는 C5가 없으면 이유를 남기고 건너뛴다.

TestStore를 사용하는 suite와 실제 스레드 검사는 `IndoorMapSerialTests`의 `.serialized` 범위 안에서 실행한다. 전역 main executor hook의 간섭을 피하기 위한 구조이며, 새 TestStore 테스트도 이 상위 suite에 둔다. 관련 없는 도면·geometry 테스트는 병렬 실행할 수 있다.

가져오기 스크립트는 IMDFData 존재 여부와 독립적으로 기존 routing·서가 파일을 검사한다. `--replace`가 없으면 변경 파일을 보존하고 중단한다. 합성 데이터로 초기 가져오기·부분 폴더·덮어쓰기 방지·명시적 교체·반복 실행을 검증한다.

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_*.py' -v
```
