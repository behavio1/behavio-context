import Foundation
import OSLog

/// Keeps access to user-selected folders across launches and joins their histories.
public actor RecordingLibrary: RecordingHistoryStore {
    private let defaults: UserDefaults
    private let defaultDirectory: URL
    private let key = "BehavioContext.RecordingFolders.v1"
    private var folders: FolderPreferences
    private var resolved: [Data: URL] = [:]
    private var scopedURLs: [URL] = []
    private let logger = Logger(subsystem: "one.behavio.context", category: "recording-storage")

    public init(defaults: UserDefaults = .standard, defaultDirectory: URL? = nil) {
        self.defaults = defaults
        self.defaultDirectory = defaultDirectory ?? RecordingStorage.recordingsDirectory()
        folders = defaults.data(forKey: "BehavioContext.RecordingFolders.v1")
            .flatMap { try? JSONDecoder().decode(FolderPreferences.self, from: $0) }
            ?? FolderPreferences()
    }

    deinit {
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
    }

    public func recordingDirectory() throws -> URL {
        guard let bookmark = folders.active else { return defaultDirectory }
        return try resolve(bookmark)
    }

    public func selectDirectory(_ url: URL) throws {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        // Verify the selected location now, before persisting a new destination.
        let probe = url.appendingPathComponent(".behavio-write-check-\(UUID().uuidString)")
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        _ = try resolve(bookmark)
        var updated = folders
        if !updated.bookmarks.contains(bookmark) { updated.bookmarks.append(bookmark) }
        updated.active = bookmark
        try persist(updated)
    }

    public func useDefaultDirectory() throws {
        var updated = folders
        updated.active = nil
        try persist(updated)
    }

    public func usesDefaultDirectory() -> Bool { folders.active == nil }

    public func load() async throws -> RecordingHistorySnapshot {
        var entries: [RecordingHistoryEntry] = []
        var selectedID = defaults.string(forKey: key + ".selection").flatMap(UUID.init(uuidString:))
        for directory in availableDirectories() {
            do {
                let snapshot = try await FileRecordingHistoryStore(recordingsDirectory: directory).load()
                entries.append(contentsOf: snapshot.recordings)
                if selectedID == nil { selectedID = snapshot.selectedRecordingID }
            } catch {
                // An unplugged older destination must not hide the other recordings.
                logger.error("Could not read a recording folder: \(error.localizedDescription, privacy: .private)")
            }
        }
        entries.sort { $0.recordedAt < $1.recordedAt }
        return RecordingHistorySnapshot(
            recordings: entries,
            selectedRecordingID: entries.contains(where: { $0.id == selectedID }) ? selectedID : entries.last?.id
        )
    }

    public func save(_ snapshot: RecordingHistorySnapshot) async throws {
        defaults.set(snapshot.selectedRecordingID?.uuidString, forKey: key + ".selection")
        for directory in availableDirectories() {
            let entries = snapshot.recordings.filter {
                $0.fileURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                    == directory.standardizedFileURL
            }
            // Do not replace a temporarily unavailable or not-yet-loaded catalog with an empty one.
            guard !entries.isEmpty else { continue }
            try await FileRecordingHistoryStore(recordingsDirectory: directory).save(
                RecordingHistorySnapshot(recordings: entries, selectedRecordingID: snapshot.selectedRecordingID)
            )
        }
    }

    public func delete(_ recording: RecordingHistoryEntry) async throws {
        let parent = recording.fileURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        guard availableDirectories().contains(where: { $0.standardizedFileURL == parent }) else {
            throw RecordingHistoryError.invalidRecordingLocation
        }
        try await FileRecordingHistoryStore(recordingsDirectory: parent).delete(recording)
    }

    private func availableDirectories() -> [URL] {
        var urls = [defaultDirectory]
        for bookmark in folders.bookmarks {
            do {
                let url = try resolve(bookmark)
                if !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { urls.append(url) }
            } catch {
                logger.error("A saved recording folder is unavailable: \(error.localizedDescription, privacy: .private)")
            }
        }
        return urls
    }

    private func resolve(_ bookmark: Data) throws -> URL {
        if let url = resolved[bookmark] { return url }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale
        )
        if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        resolved[bookmark] = url
        if stale {
            let refreshed = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )
            var updated = folders
            updated.bookmarks = updated.bookmarks.map { $0 == bookmark ? refreshed : $0 }
            if updated.active == bookmark { updated.active = refreshed }
            try persist(updated)
            resolved[refreshed] = url
        }
        return url
    }

    private func persist(_ updated: FolderPreferences) throws {
        defaults.set(try JSONEncoder().encode(updated), forKey: key)
        folders = updated
    }
}

private struct FolderPreferences: Codable {
    var bookmarks: [Data] = []
    var active: Data?
}
