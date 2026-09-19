@preconcurrency import AVFoundation
import Foundation

public enum LocalSpeechError: Error, LocalizedError {
    case unavailable(String)
    public var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
}

/// Runs the bundled native engine inside the app sandbox. No service, Python, or network access.
public enum LocalWhisperTranscriber {
    public static var executableURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-cli")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    public static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BehavioContext/SpeechModels", isDirectory: true)
    }
    public static func modelURL(_ engine: SpeechEngine) -> URL {
        modelsDirectory.appendingPathComponent(engine.modelName ?? "unconfigured")
    }

    public static func transcribe(recordingURL: URL, settings: SpeechSettings, executable: URL? = nil, model: URL? = nil) async throws -> [TranscriptSegment] {
        guard let executable = executable ?? executableURL else {
            throw LocalSpeechError.unavailable("The local Whisper runtime is missing. Reinstall the app.")
        }
        let model = model ?? modelURL(settings.engine)
        guard FileManager.default.isReadableFile(atPath: model.path) else {
            throw LocalSpeechError.unavailable("Choose a local Whisper model in Speech Recognition settings.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("audio.wav")
        let audioDurationMs = try await extractAudio(recordingURL, to: audio)
        let output = directory.appendingPathComponent("transcript")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-m", model.path, "-f", audio.path, "-l", settings.language.code,
                             "-oj", "-of", output.path, "-np", "-t", "4"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(600)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else {
                    throw LocalSpeechError.unavailable("Local transcription timed out. Try the Small model.")
                }
                try await Task.sleep(for: .milliseconds(150))
            }
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw LocalSpeechError.unavailable("Whisper could not transcribe the audio. Check the selected model file.")
        }
        return try decode(Data(contentsOf: output.appendingPathExtension("json"))).compactMap { segment in
            guard segment.startMs < audioDurationMs else { return nil }
            return TranscriptSegment(id: segment.id, startMs: segment.startMs, endMs: min(segment.endMs, audioDurationMs), text: segment.text, words: segment.words)
        }
    }

    public static func decode(_ data: Data) throws -> [TranscriptSegment] {
        struct Output: Decodable {
            struct Segment: Decodable {
                struct Offsets: Decodable { let from: Int; let to: Int }
                let offsets: Offsets
                let text: String
            }
            let transcription: [Segment]
        }
        return try JSONDecoder().decode(Output.self, from: data).transcription.enumerated().compactMap { index, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, segment.offsets.from >= 0, segment.offsets.to >= segment.offsets.from else { return nil }
            return TranscriptSegment(id: String(format: "segment-%03d", index + 1), startMs: segment.offsets.from, endMs: segment.offsets.to, text: text)
        }
    }

    private static func extractAudio(_ input: URL, to output: URL) async throws -> Int {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw LocalSpeechError.unavailable("The recording has no audio track. Enable the microphone before recording.")
        }
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(trackOutput)
        guard reader.startReading() else { throw reader.error ?? LocalSpeechError.unavailable("Could not read the recorded audio.") }
        FileManager.default.createFile(atPath: output.path, contents: Data(count: 44))
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        try file.seekToEnd()
        var byteCount: UInt32 = 0
        while let sample = trackOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(block)
            guard count <= Int(UInt32.max - byteCount - 36) else { throw LocalSpeechError.unavailable("The recording is too long for local transcription.") }
            var bytes = Data(count: count)
            let copied = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!) }
            guard copied == kCMBlockBufferNoErr else { throw LocalSpeechError.unavailable("Could not decode recorded audio.") }
            try file.write(contentsOf: bytes)
            byteCount += UInt32(count)
        }
        guard reader.status == .completed, byteCount > 0 else { throw reader.error ?? LocalSpeechError.unavailable("The recording contains no usable audio.") }
        var header = Data()
        func text(_ value: String) { header.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of: &value) { header.append(contentsOf: $0) } }
        text("RIFF"); number(byteCount + 36); text("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(16000)); number(UInt32(32000))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(byteCount)
        try file.seek(toOffset: 0)
        try file.write(contentsOf: header)
        return Int(byteCount) / 32
    }
}
