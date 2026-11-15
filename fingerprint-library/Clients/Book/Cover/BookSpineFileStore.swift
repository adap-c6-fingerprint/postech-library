import Foundation

nonisolated struct BookSpineFileStore: Sendable {
    let directory: URL

    static let live = Self(
        directory: URL.applicationSupportDirectory
            .appendingPathComponent("BookSpineCache-v1", isDirectory: true)
    )
    // 앱을 다시 켜도 남도록 Application Support에 둔다. iCloud 백업에서는 제외한다.

    func fileURL(isbn13: String) -> URL {
        directory.appendingPathComponent("\(isbn13).png")
    }

    func missingMarkerURL(isbn13: String) -> URL {
        directory.appendingPathComponent("\(isbn13).none")
    }
    // Yes24에 책등이 없다고 확인된 책을 표시하는 빈 파일. 있으면 API를 다시 부르지 않는다.

    func save(_ data: Data, isbn13: String) throws {
        try prepareDirectory()
        try data.write(to: fileURL(isbn13: isbn13), options: .atomic)
    }

    func markMissing(isbn13: String) throws {
        try prepareDirectory()
        try Data().write(to: missingMarkerURL(isbn13: isbn13), options: .atomic)
    }

    func isMarkedMissing(isbn13: String) -> Bool {
        FileManager.default.fileExists(atPath: missingMarkerURL(isbn13: isbn13).path)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
}
