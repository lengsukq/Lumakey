import Foundation
import LumakeyCore

func testV071WorkspaceOperations() throws {
    let fm = FileManager.default
    let root = try makeTempDir("workspace-ops")
    var cleanupTrashURLs: [URL] = []
    defer {
        for trashed in cleanupTrashURLs {
            if trashed.lastPathComponent.contains("lmky-trash-probe-") {
                try? fm.removeItem(at: trashed)
            }
        }
        try? fm.removeItem(at: root)
    }

    let paneADir = try WorkspaceFileOperations.createFolder(named: "PaneA", in: root)
    let paneBDir = try WorkspaceFileOperations.createFolder(named: "PaneB", in: root)
    check(fm.fileExists(atPath: paneADir.path) && fm.fileExists(atPath: paneBDir.path), "createFolder creates directories")

    var duplicateFolderRejected = false
    do {
        _ = try WorkspaceFileOperations.createFolder(named: "PaneA", in: root)
    } catch let LumakeyError.renameConflict(detail) {
        duplicateFolderRejected = detail.contains("PaneA")
    }
    check(duplicateFolderRejected, "createFolder rejects existing folder name")

    let reportURL = paneADir.appendingPathComponent("report.pdf")
    try Data("PDF-V1".utf8).write(to: reportURL)

    // Illegal & empty rename interception
    for badName in ["", "   ", ".", "..", "bad/name.pdf", "bad:name.pdf"] {
        var rejected = false
        do {
            _ = try WorkspaceFileOperations.renameItem(at: reportURL, to: badName)
        } catch LumakeyError.invalidRenameTarget {
            rejected = true
        }
        check(rejected, "renameItem rejects illegal name '\(badName)'")
    }

    // Single-file rename + conflict interception
    let renamedURL = try WorkspaceFileOperations.renameItem(at: reportURL, to: "annual_report.pdf")
    check(!fm.fileExists(atPath: reportURL.path) && fm.fileExists(atPath: renamedURL.path), "renameItem renames file cleanly")

    let otherURL = paneADir.appendingPathComponent("memo.pdf")
    try Data("MEMO".utf8).write(to: otherURL)
    var conflictRejected = false
    do {
        _ = try WorkspaceFileOperations.renameItem(at: otherURL, to: "annual_report.pdf")
    } catch LumakeyError.renameConflict {
        conflictRejected = true
    }
    check(conflictRejected, "renameItem blocks overwriting existing file")

    // Rename back to report.pdf and verify lossless duplicate copy naming ("report 副本.pdf", "report 副本 2.pdf")
    let baseReport = try WorkspaceFileOperations.renameItem(at: renamedURL, to: "report.pdf")
    let copy1 = try WorkspaceFileOperations.copyItems([baseReport], to: paneADir)
    let copy2 = try WorkspaceFileOperations.copyItems([baseReport], to: paneADir)
    check(copy1.first?.lastPathComponent == "report 副本.pdf", "first same-dir copy named 'report 副本.pdf'")
    check(copy2.first?.lastPathComponent == "report 副本 2.pdf", "second same-dir copy named 'report 副本 2.pdf'")
    check((try? String(contentsOf: copy2[0], encoding: .utf8)) == "PDF-V1", "copied file preserves exact content")

    // Cross-directory copy with conflict avoidance
    let crossCopy1 = try WorkspaceFileOperations.copyItems([baseReport], to: paneBDir)
    let crossCopy2 = try WorkspaceFileOperations.copyItems([baseReport], to: paneBDir)
    check(crossCopy1.first?.lastPathComponent == "report.pdf", "first cross-dir copy keeps original name")
    check(crossCopy2.first?.lastPathComponent == "report 副本.pdf", "second cross-dir copy avoids overwriting existing file")

    // Cross-directory move + destination conflict interception
    let movedMemo = try WorkspaceFileOperations.moveItems([otherURL], to: paneBDir)
    check(!fm.fileExists(atPath: otherURL.path) && fm.fileExists(atPath: movedMemo[0].path), "moveItems moves file across directories")

    var moveConflictBlocked = false
    do {
        _ = try WorkspaceFileOperations.moveItems([baseReport], to: paneBDir)
    } catch LumakeyError.renameConflict {
        moveConflictBlocked = true
    }
    check(moveConflictBlocked && fm.fileExists(atPath: baseReport.path), "moveItems blocks overwriting existing file in destination")

    // Block moving or copying parent folder into itself or its own descendant
    let nestedChild = try WorkspaceFileOperations.createFolder(named: "Nested", in: paneADir)
    var selfMoveBlocked = false
    do {
        _ = try WorkspaceFileOperations.moveItems([paneADir], to: nestedChild)
    } catch let LumakeyError.fileOperationBlocked(title, _, _) {
        selfMoveBlocked = title.contains("无法移动")
    }
    check(selfMoveBlocked && fm.fileExists(atPath: paneADir.path), "moveItems blocks moving parent directory into child directory")

    var selfCopyBlocked = false
    do {
        _ = try WorkspaceFileOperations.copyItems([paneADir], to: nestedChild)
    } catch let LumakeyError.fileOperationBlocked(title, _, _) {
        selfCopyBlocked = title.contains("无法复制")
    }
    check(selfCopyBlocked, "copyItems blocks copying directory into its own child directory")

    // Read-only NTFS volume interception & diagnostic verification
    let fakeNTFSVolume = VolumeSummary(
        name: "BackupNTFS",
        mountPath: "/Volumes/BackupNTFS",
        fileSystemType: "ntfs",
        formatKind: .ntfsReadOnly,
        isReadOnly: true,
        isExternal: true,
        totalBytes: 1_000_000_000,
        availableBytes: 500_000_000
    )
    let ntfsInspector: (URL) -> VolumeSummary? = { _ in fakeNTFSVolume }

    var ntfsCreateBlocked = false
    do {
        _ = try WorkspaceFileOperations.createFolder(named: "Blocked", in: paneADir, inspectVolume: ntfsInspector)
    } catch let err as LumakeyError {
        ntfsCreateBlocked = err.diagnostic.title.contains("只读") && err.diagnostic.reason.contains("BackupNTFS")
    }
    check(ntfsCreateBlocked, "NTFS read-only volume blocks createFolder with clear diagnostic")

    var ntfsTrashBlocked = false
    do {
        _ = try WorkspaceFileOperations.trashItems([copy1[0]], inspectVolume: ntfsInspector)
    } catch let err as LumakeyError {
        ntfsTrashBlocked = err.diagnostic.title.contains("只读")
    }
    check(ntfsTrashBlocked && fm.fileExists(atPath: copy1[0].path), "NTFS read-only volume blocks trashItems safely")

    // Safe system Trash verification (trashItem, never permanent removeItem)
    let uniqueProbeName = "lmky-trash-probe-\(UUID().uuidString.prefix(8)).txt"
    let probeURL = paneADir.appendingPathComponent(uniqueProbeName)
    try Data("SAFE-TRASH".utf8).write(to: probeURL)
    let trashedResult = try WorkspaceFileOperations.trashItems([probeURL])
    cleanupTrashURLs.append(contentsOf: trashedResult)
    check(!fm.fileExists(atPath: probeURL.path), "trashItems removes item from source directory")
    check(trashedResult.count == 1 && fm.fileExists(atPath: trashedResult[0].path), "trashItems places item safely in system Trash")

    // Clipboard state deduplication & membership
    let clip = WorkspaceClipboardState(urls: [baseReport, baseReport, copy1[0]], mode: .cutMove)
    check(clip.urls.count == 2 && clip.contains(baseReport), "WorkspaceClipboardState deduplicates URLs and matches paths")

    print("[ok] v0.7.1 WorkspaceFileOperations (CreateFolder + Rename + Safe Copy/Move + Parent-Into-Child Guard + NTFS ReadOnly Guard + System Trash)")
}
