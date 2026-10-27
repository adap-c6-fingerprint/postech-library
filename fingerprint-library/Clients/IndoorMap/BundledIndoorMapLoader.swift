import Foundation

/// 번들 또는 지정한 폴더의 IMDF를 읽어 화면과 길찾기에서 사용할 지도 모델로 변환한다.
///
/// JSON 해석은 DTO가, 좌표·층 참조 검증은 ``IMDFMapper``가 담당한다.
/// 노드와 서가 매핑은 별도 자료이므로 이 로더의 결과만으로 길찾기가 준비되지는 않는다.
nonisolated struct BundledIndoorMapLoader {
    /// 화면 지도와 navigation이 함께 고정해야 하는 필수·선택 파일 계약.
    private static let requiredFiles = ["manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
                                        "unit.geojson", "fixture.geojson", "opening.geojson"]
    private static let optionalFiles = ["amenity.geojson", "section.geojson"]

    /// 필수 파일과 실제로 존재하는 선택 파일을 반환한다.
    /// 필수 파일이 없더라도 목록에서 빼지 않아 후속 읽기에서 누락을 오류로 보고한다.
    static func fileNames(in directory: URL) -> [String] {
        requiredFiles + optionalFiles.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// 앱 기본 리소스인 포스텍 도서관 도면을 엄격한 검증 정책으로 읽는다.
    ///
    /// - Parameter bundle: `IndoorMaps/POSTECHLibrary/IMDFData`를 포함하는 번들.
    /// - Returns: 원본 층 ID와 도형을 보존한 도서관 지도.
    /// - Throws: 리소스 누락·형식 오류를 나타내는 ``IndoorMapLoadError`` 또는 `CancellationError`.
    func loadLibrary(in bundle: Bundle = .main) async throws -> IndoorMap {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/POSTECHLibrary/IMDFData")
        }
        return try await load(
            directory: root.appending(path: "POSTECHLibrary/IMDFData", directoryHint: .isDirectory)
        )
    }

    /// 기존 개발 도면을 회귀 검증용으로 읽는다. 앱의 기본 지도 진입점은 `loadLibrary(in:)`다.
    ///
    /// 타입 간 UUID 충돌이 있는 원본을 위해 호환 정책을 적용하고 진단 정보를 남긴다.
    /// - Parameter bundle: `IndoorMaps/C5/IMDFData`를 포함하는 번들.
    /// - Returns: 호환 정책으로 해석한 지도와 진단 정보.
    /// - Throws: 리소스 누락·형식 오류 또는 작업 취소 오류.
    func loadC5(in bundle: Bundle = .main) async throws -> IndoorMap {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/C5/IMDFData")
        }
        return try await load(
            directory: root.appending(path: "C5/IMDFData", directoryHint: .isDirectory),
            policy: .c5Compatibility
        )
    }

    /// IMDF 1.0.0 폴더를 읽고 지도에 필요한 파일·도형·층 연결을 검증한다.
    ///
    /// `amenity`와 `section`은 선택 파일이다. 없으면 해당 요소를 제외하되,
    /// 존재하는 파일의 손상은 오류로 처리한다. 파일 I/O·디코딩·변환은 MainActor 밖에서 실행한다.
    /// - Parameters:
    ///   - directory: `manifest.json`과 GeoJSON 파일들이 직접 들어 있는 폴더.
    ///   - policy: 타입 간 중복 UUID를 거부할지, 호환 진단으로 남길지 정하는 정책.
    /// - Returns: 층 ordinal 순으로 정렬된 ``IndoorMap``.
    /// - Throws: ``IndoorMapLoadError`` 또는 `CancellationError`.
    @concurrent
    func load(directory: URL, policy: IMDFImportPolicy = .strict) async throws -> IndoorMap {
        try Task.checkCancellation()
        let manifest: IMDFManifestDTO = try decode("manifest.json", in: directory)
        guard manifest.version == "1.0.0" else {
            throw IndoorMapLoadError.invalidData(
                file: "manifest.json", reason: "지원하지 않는 IMDF 버전입니다: \(manifest.version)"
            )
        }
        var collections: [String: IMDFFeatureCollectionDTO] = [:]
        for file in Self.fileNames(in: directory) where file != "manifest.json" {
            try Task.checkCancellation()
            let kind = String(file.dropLast(".geojson".count))
            collections[kind] = try decode(file, in: directory)
        }
        return try IMDFMapper().map(version: manifest.version, collections: collections, policy: policy)
    }

    /// 파일 누락과 JSON 해석 실패를 구분해 오류에 원본 파일명을 포함한다.
    private func decode<T: Decodable>(_ file: String, in directory: URL) throws -> T {
        let url = directory.appendingPathComponent(file)
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw IndoorMapLoadError.missingResource(file)
        } catch {
            throw IndoorMapLoadError.invalidData(file: file, reason: error.localizedDescription)
        }
    }
}
