import CryptoKit
import Foundation

public struct SpeechModelDownload: Sendable {
    public let engine: SpeechEngine
    public var byteCount: Int64 { engine == .whisperSmall ? 487601967 : 1624555275 }
    public var checksum: String {
        engine == .whisperSmall
            ? "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
            : "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    }
    public init(engine: SpeechEngine) { self.engine = engine }

    public func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let name = engine.modelName else { return }
        let existing = LocalWhisperTranscriber.modelURL(engine)
        if FileManager.default.isReadableFile(atPath: existing.path), (try? validate(existing)) != nil {
            progress(1)
            return
        }
        // GET-only public model weights. Audio and transcripts never enter this request.
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 3600
        let delegate = DownloadProgress(progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalSpeechError.unavailable("The model download failed. Check your connection and try again.")
        }
        try Task.checkCancellation()
        try validate(temporary)
        try FileManager.default.createDirectory(at: LocalWhisperTranscriber.modelsDirectory, withIntermediateDirectories: true)
        let destination = LocalWhisperTranscriber.modelURL(engine)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    public func validate(_ file: URL) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == Int(byteCount) else { throw LocalSpeechError.unavailable("The model file is incomplete. Download it again.") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw LocalSpeechError.unavailable("The model file failed verification. Download it again.") }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
}
