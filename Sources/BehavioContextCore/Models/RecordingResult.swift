import Foundation

public struct RecordingResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let contextDirectoryURL: URL?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        contextDirectoryURL: URL? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        let derivedContextURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("context", isDirectory: true)
        self.contextDirectoryURL = contextDirectoryURL
            ?? (FileManager.default.fileExists(atPath: derivedContextURL.path) ? derivedContextURL : nil)
        self.recordedAt = recordedAt
    }

    public var context: String {
        contextDirectoryURL?.path ?? fileURL.path
    }
}
