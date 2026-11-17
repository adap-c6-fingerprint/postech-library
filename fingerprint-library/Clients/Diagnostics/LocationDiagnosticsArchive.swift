import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// 위치 진단 기록 폴더 하나를 ZIP 파일 하나로 내보낸다(실험 브랜치 전용).
/// 공유 시트가 실제로 파일을 요청할 때만 압축하므로 목록을 그리는 동안에는 파일을 만들지 않는다.
nonisolated struct LocationDiagnosticsArchive: Transferable, Sendable {
    let sessionID: String
    let folderURL: URL

    init(session: LocationDiagnosticsSessionInfo) {
        sessionID = session.id
        folderURL = session.folderURL
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(try archive.makeZip())
        }
    }

    /// `<기록 ID>.zip`을 만든다. 풀면 `<기록 ID>/` 폴더 안에 기록 파일이 그대로 들어 있다.
    /// 같은 기록을 동시에 내보내도 겹치지 않도록 내보낼 때마다 새 임시 폴더를 쓴다.
    func makeZip(in directory: URL = .temporaryDirectory, now: Date = Date()) throws -> URL {
        let exportRoot = directory.appending(path: "LocationDiagnosticsExport", directoryHint: .isDirectory)
        Self.removeStaleExports(in: exportRoot, before: now.addingTimeInterval(-Self.staleExportAge))
        let exportFolder = exportRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let destination = exportFolder.appending(path: "\(sessionID).zip")

        // 폴더를 `.forUploading`으로 읽으면 시스템이 ZIP을 만들어 준다. 블록이 끝나면 지워지므로 바로 옮긴다.
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folderURL, options: .forUploading,
                                       error: &coordinationError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }

    /// 공유 시트는 한 번 공유할 때도 파일을 여러 번 요청해 ZIP이 여러 개 생긴다.
    /// 화면 녹화가 들어 있으면 크기가 커서, 지금 공유 중일 리 없는 오래된 내보내기만 정리한다.
    static let staleExportAge: TimeInterval = 10 * 60

    private static func removeStaleExports(in exportRoot: URL, before cutoff: Date) {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: exportRoot, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for folder in folders {
            let createdAt = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if createdAt < cutoff { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
