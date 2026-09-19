import Foundation
import Observation

@MainActor @Observable
public final class SpeechModelInstaller {
    public private(set) var downloading: SpeechEngine?
    public private(set) var isImporting = false
    public private(set) var progress = 0.0
    public private(set) var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    public init() {}

    public func download(_ engine: SpeechEngine, completion: @escaping @MainActor @Sendable () -> Void) {
        guard engine != .apple, downloading == nil else { return }
        downloading = engine
        isImporting = false
        progress = 0
        error = nil
        task = Task.detached { [self] in
            do {
                try await SpeechModelDownload(engine: engine).install { value in
                    Task { @MainActor [self] in self.progress = value }
                }
                await self.finished(error: nil)
            } catch {
                await self.finished(error: Task.isCancelled ? nil : error.localizedDescription)
            }
            await completion()
        }
    }
    public func importModel(from selection: URL, engine: SpeechEngine, completion: @escaping @MainActor @Sendable () -> Void) {
        guard engine != .apple, downloading == nil else { return }
        downloading = engine
        isImporting = true
        progress = 0
        error = nil
        task = Task.detached { [self] in
            let access = selection.startAccessingSecurityScopedResource()
            defer { if access { selection.stopAccessingSecurityScopedResource() } }
            do {
                let isDirectory = (try selection.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                let candidates = isDirectory
                    ? [selection.appendingPathComponent(engine.modelName!), selection.appendingPathComponent("ggml-model.bin")]
                    : [selection]
                guard let source = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
                    throw LocalSpeechError.unavailable("No compatible model found. Choose a ggml .bin model. Existing .pt or MLX weights need local conversion; nothing will be downloaded automatically.")
                }
                guard source.pathExtension.lowercased() == "bin" else {
                    throw LocalSpeechError.unavailable("This model format needs local conversion to ggml .bin. No model will be downloaded automatically.")
                }
                let directory = LocalWhisperTranscriber.modelsDirectory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = LocalWhisperTranscriber.modelURL(engine)
                if source.standardizedFileURL != destination.standardizedFileURL {
                    let staging = directory.appendingPathComponent(UUID().uuidString + ".partial")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try FileManager.default.copyItem(at: source, to: staging)
                    try SpeechModelDownload(engine: engine).validate(staging)
                    try Task.checkCancellation()
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                    } else {
                        try FileManager.default.moveItem(at: staging, to: destination)
                    }
                } else {
                    try SpeechModelDownload(engine: engine).validate(destination)
                }
                await finished(error: nil)
            } catch {
                await finished(error: Task.isCancelled ? nil : error.localizedDescription)
            }
            await completion()
        }
    }

    public func cancel() { task?.cancel() }
    private func finished(error: String?) {
        self.error = error
        downloading = nil
        isImporting = false
        task = nil
    }
}
