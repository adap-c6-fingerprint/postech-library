# C5 IMDF 로컬 평가 데이터

기존 `2026-C6-M06-Fingerprint` 프로젝트의 C5 도면을 로컬에서 불러온다. 도면에는 Apple 샘플 데이터가 포함되어 있고, 동봉된 `LICENSE/LICENSE.txt`는 내부 테스트·평가 용도로 사용을 제한하며 재배포를 허용하지 않는다. 따라서 C5 데이터와 출처 기록은 Git에서 제외한다. 외부 공유 앱·배포물에 포함하기 전에는 재배포 가능한 데이터로 교체해야 한다.

## 가져오기

두 저장소가 같은 상위 폴더에 있으면 프로젝트 루트에서 실행한다.

```sh
python3 Scripts/import-c5-local.py
```

다른 위치에 있으면 원본 저장소 경로를 지정한다.

```sh
python3 Scripts/import-c5-local.py --source /path/to/2026-C6-M06-Fingerprint
```

원본 저장소는 수정하지 않는다. 커밋되지 않은 파일을 포함한 현재 C5 리소스 13개를 그대로 복사하고 원본 commit·변경 파일·파일별 SHA-256을 `fingerprint-library/Resources/IndoorMaps/C5/source.json`에 기록한다. 기존 로컬 복사본과 다르면 중단하며, 검토 후 `--replace`로 교체할 수 있다. 도면을 수정했다면 다시 빌드해야 앱 번들이 갱신된다.

Xcode는 `Resources/IndoorMaps`를 폴더 리소스로 복사한다. 앱 번들 경로는 `IndoorMaps/C5/IMDFData/`이며, 파일 이름·디렉터리 구조와 라이선스를 유지한다. 로컬 데이터가 없어도 앱은 빌드되며, 로더를 호출하면 `missingResource` 오류를 반환한다.

## 로딩 범위

`BundledIndoorMapLoader().loadC5()`는 파일 I/O와 디코딩을 MainActor 밖에서 실행한다. DTO → Mapper → Domain 순서로 변환하며 다음을 확인한다.

- IMDF `manifest.version == 1.0.0`, FeatureCollection·Feature·feature_type·UUID와 같은 파일 안의 중복 ID
- `[경도, 위도]` WGS 84 좌표 범위, LineString 길이, Polygon·MultiPolygon의 닫힌 ring과 내부 ring 보존
- 층 ordinal과 표시 이름, unit·fixture·opening의 level_id 참조
- amenity의 unit_ids·level_id가 가리키는 층: 참조가 없거나 여러 층으로 모순되면 오류

렌더링용으로 venue·level·footprint·unit·fixture·opening·amenity를 해석한다. address·building·anchor·occupant는 원본 보관 대상이며, 아직 도메인 모델로 변환하지 않는다. 전체 IMDF 규격 인증을 수행하는 검증기는 아니다. `manifest.version`은 형식 버전이며 지도 개정 번호가 아니다.

원본 C5는 unit과 amenity 사이에 UUID 중복 1건이 있다. 일반 `load(directory:)`는 타입 간 중복도 거부한다. C5 진입점만 `c5Compatibility` 정책으로 읽고 `diagnostics`에 중복을 남긴다. 화면용 요소 ID는 종류와 원본 UUID의 조합으로 구분하며 원본 UUID를 재작성하지 않는다. 새 도서관 데이터에는 이 호환 정책을 적용하지 않는다.

C5 fixture는 책상 등 시설이다. 표시 이름을 실제 도서관 서가 키로 사용하지 않는다. MapKit 화면·위치 기능은 [실내지도 구현 문서](IndoorMapFeature.md)를 참고한다. routing GeoJSON·ShelfDirectory 연결은 #5의 후속 범위다.

## 위치 데이터

현재 참고 프로젝트에는 별도 Wi-Fi 측위 모델·수집 데이터·Core Location 서비스 구현이 없다. Apple 실내 측위용 fingerprint는 도면 파일과 별개로 iOS의 Core Location이 서버에서 내려받아 사용한다. 도면 복사가 측위 활성화를 보장하지는 않는다. C5 활성 상태와 새 앱의 위치·층 정보 품질은 실제 기기에서 확인해야 한다. [Apple Indoor Maps Program 설명](https://developer.apple.com/videos/play/wwdc2019/245/)

## 검증

공유 scheme의 `IndoorMapTests`에서 외부 데이터를 포함하지 않는 테스트용 GeoJSON으로 정상·손상·참조 오류·내부 ring·C5 호환 진단을 확인한다.

로컬 C5를 가져오면 추가로 실제 앱 번들 로딩과 13개 파일의 SHA-256을 검증한다. C5가 없으면 이 두 테스트는 이유를 표시하고 건너뛰며, 실행하지 않은 검증을 통과로 취급하지 않는다.

```sh
xcodebuild -project fingerprint-library.xcodeproj -scheme fingerprint-library \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```
