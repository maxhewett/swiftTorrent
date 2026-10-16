import Foundation

final class PeriodicCleanupPauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }

    func waitUntilResumed() -> Bool {
        while !Task.isCancelled {
            lock.lock()
            let shouldWait = paused
            lock.unlock()
            if !shouldWait { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}

struct PeriodicCleanupPayload: Sendable {
    let root: URL
    let name: String
    let relativePaths: [String]
    let category: String?
}

struct PeriodicCleanupScanResult: Sendable {
    let payloads: [PeriodicCleanupPayload]
    let errorMessage: String?
}

enum PeriodicCleanupScanner {
    struct Filter: Sendable {
        let autoFilterNonMediaFiles: Bool
        let exclusionRules: [FileExclusionRule]

        nonisolated func shouldInclude(_ path: String, category: String?) -> Bool {
            let ext = URL(fileURLWithPath: path).pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !ext.isEmpty else { return false }
            let categoryID = category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if exclusionRules.contains(where: { rule in
                rule.fileExtension.lowercased() == ext && (rule.appliesToAllCategories || categoryID.map { rule.categoryIDs.contains($0) } == true)
            }) { return false }
            return !autoFilterNonMediaFiles || MediaFileFilter.allowedExtensions.contains(ext)
        }
    }

    nonisolated static func scan(in root: URL, category: String?, excludedRoots: Set<String>, filter: Filter, pauseGate: PeriodicCleanupPauseGate) -> PeriodicCleanupScanResult {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            return PeriodicCleanupScanResult(payloads: [], errorMessage: error.localizedDescription)
        }

        var payloads: [PeriodicCleanupPayload] = []
        var rootFiles: [String] = []
        for child in children {
            guard pauseGate.waitUntilResumed() else { break }
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if excludedRoots.contains(child.standardizedFileURL.path) { continue }
                let files = mediaFiles(in: child, relativeTo: child, depth: 0, category: category, excludedRoots: excludedRoots, filter: filter, pauseGate: pauseGate)
                if !files.isEmpty {
                    payloads.append(PeriodicCleanupPayload(root: child, name: child.lastPathComponent, relativePaths: files.sorted(), category: category))
                }
            } else if values.isRegularFile == true, filter.shouldInclude(child.path, category: category) {
                rootFiles.append(child.lastPathComponent)
            }
        }

        for path in rootFiles.sorted() {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            payloads.append(PeriodicCleanupPayload(root: root, name: name, relativePaths: [path], category: category))
        }
        return PeriodicCleanupScanResult(payloads: payloads, errorMessage: nil)
    }

    nonisolated private static func mediaFiles(
        in directory: URL,
        relativeTo base: URL,
        depth: Int,
        category: String?,
        excludedRoots: Set<String>,
        filter: Filter,
        pauseGate: PeriodicCleanupPauseGate
    ) -> [String] {
        guard depth <= 5,
              let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }
        var result: [String] = []
        for child in children {
            guard pauseGate.waitUntilResumed() else { break }
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if excludedRoots.contains(child.standardizedFileURL.path) { continue }
                result.append(contentsOf: mediaFiles(in: child, relativeTo: base, depth: depth + 1, category: category, excludedRoots: excludedRoots, filter: filter, pauseGate: pauseGate))
            } else if values.isRegularFile == true, filter.shouldInclude(child.path, category: category) {
                let basePath = base.standardizedFileURL.path
                let childPath = child.standardizedFileURL.path
                let relative = String(childPath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relative.isEmpty { result.append(relative) }
            }
        }
        return result
    }
}
