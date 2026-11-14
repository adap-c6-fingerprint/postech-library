import Foundation

nonisolated struct BundledIndoorMapLoader {
    private static let requiredFiles = ["manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
                                        "unit.geojson", "fixture.geojson", "opening.geojson"]
    private static let optionalFiles = ["amenity.geojson", "section.geojson"]

    static func fileNames(in directory: URL) -> [String] {
        requiredFiles + optionalFiles.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    func loadLibrary(in bundle: Bundle = .main) async throws -> IndoorMap {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/POSTECHLibrary/IMDFData")
        }
        return try await load(
            directory: root.appending(path: "POSTECHLibrary/IMDFData", directoryHint: .isDirectory)
        )
    }

    @concurrent
    func load(directory: URL) async throws -> IndoorMap {
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
        return try IMDFMapper().map(version: manifest.version, collections: collections)
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
