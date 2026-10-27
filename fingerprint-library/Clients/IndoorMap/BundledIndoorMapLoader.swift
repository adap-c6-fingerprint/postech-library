import Foundation

nonisolated struct BundledIndoorMapLoader {
    func loadLibrary(in bundle: Bundle = .main) async throws -> IndoorMap {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/POSTECHLibrary/IMDFData")
        }
        return try await load(
            directory: root.appending(path: "POSTECHLibrary/IMDFData", directoryHint: .isDirectory)
        )
    }

    func loadC5(in bundle: Bundle = .main) async throws -> IndoorMap {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/C5/IMDFData")
        }
        return try await load(
            directory: root.appending(path: "C5/IMDFData", directoryHint: .isDirectory),
            policy: .c5Compatibility
        )
    }

    /// 파일 I/O와 디코딩은 호출자의 MainActor에서 실행하지 않는다.
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
        for file in ["venue", "level", "footprint", "unit", "fixture", "opening"] {
            try Task.checkCancellation()
            collections[file] = try decode("\(file).geojson", in: directory)
        }
        for file in ["amenity", "section"] {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent("\(file).geojson")
            if FileManager.default.fileExists(atPath: url.path) {
                collections[file] = try decode("\(file).geojson", in: directory)
            }
        }
        return try IMDFMapper().map(version: manifest.version, collections: collections, policy: policy)
    }

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
