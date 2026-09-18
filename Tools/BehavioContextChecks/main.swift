@preconcurrency import AVFoundation
import BehavioContextCore
import CoreVideo
import Foundation
import ImageIO

@main
enum BehavioContextChecks {
    static func main() async throws {
        if CommandLine.arguments.count == 3,
           CommandLine.arguments[1] == "--reprocess" {
            try await reprocessRecording(
                at: URL(fileURLWithPath: CommandLine.arguments[2])
            )
            return
        }
        try await checkRecordingFolders()
        if CommandLine.arguments.contains("--check-storage") { return }
        try await checkDelayedVideo()
        if CommandLine.arguments.contains("--check-timing") { return }
        try await checkPartialSuccess()
        try checkLanguageSelection()
        try await checkMultipleWindows()
        try checkMomentSelection()
        try await checkContextPackage()
        print("PASS: Behavio Context deterministic core and package checks")
    }

    private static func reprocessRecording(at recordingURL: URL) async throws {
        let manifestURL = recordingURL.deletingLastPathComponent()
            .appendingPathComponent("context/manifest.json")
        let previous = try JSONDecoder().decode(
            AgentContextManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let window = WindowSource(
            windowID: previous.windowTimeline?.first?.windowID ?? 1,
            title: previous.source.windowTitle,
            applicationName: previous.source.applicationName,
            applicationBundleIdentifier: previous.source.bundleIdentifier,
            processIdentifier: 1,
            pixelWidth: previous.source.initialPixelWidth,
            pixelHeight: previous.source.initialPixelHeight,
            frame: CGRect(
                x: 0,
                y: 0,
                width: previous.source.initialPixelWidth,
                height: previous.source.initialPixelHeight
            ),
            backingScaleFactor: 1
        )
        let visualChanges = previous.visualMoments
            .filter { $0.reason == .visualChange }
            .map(\.timeMs)
        let compilation = try await AgentContextPackageWriter().compile(
            recordingURL: recordingURL,
            source: .window(window),
            durationMs: previous.durationMs,
            microphone: previous.microphone,
            transcriptStatus: previous.transcriptStatus,
            transcript: previous.transcriptSegments,
            pointerEvents: previous.pointerEvents,
            visualChangeTimesMs: visualChanges,
            windowTimeline: previous.windowTimeline ?? []
        )
        print("PASS: reprocessed \(compilation.directoryURL.path)")
    }

    @MainActor
    private static func checkPartialSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("behavio-partial-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = directory.appendingPathComponent("recording.mp4")
        try await makeVideo(at: video)
        let source = CaptureSource.window(WindowSource(windowID: 1, title: "Test", applicationName: "Test", applicationBundleIdentifier: "test", processIdentifier: 1, pixelWidth: 640, pixelHeight: 360, frame: CGRect(x: 0, y: 0, width: 640, height: 360), backingScaleFactor: 1))
        let history = FileRecordingHistoryStore(recordingsDirectory: root)
        let store = RecordingSessionStore(sourceCatalog: CheckCatalog(source: source), captureAuthorization: CheckAuthorization(), preferencesStore: CheckPreferences(), historyStore: history, recordingPipeline: PartialSuccessPipeline(video: video))
        await store.initialize()
        store.startRecording(with: source)
        for _ in 0..<100 where !store.phase.isRecording { try await Task.sleep(for: .milliseconds(10)) }
        try require(store.phase.isRecording, "partial success test did not start")
        store.stopRecording()
        for _ in 0..<200 where store.configurationIsLocked { try await Task.sleep(for: .milliseconds(10)) }
        try require(store.phase == .idle, "saved MP4 incorrectly failed the entire session")
        try require(store.recordingFailureNotice?.kind == .contextUnavailable, "context failure notice missing")
        try require(store.recordingFailureNotice?.recoveryURL == video, "saved video inaccessible from notice")
        try require(store.selectedRecordingResult?.fileURL == video, "saved video missing from library")
        let persisted = try await history.load()
        try require(persisted.recordings.contains { $0.fileURL == video }, "saved video missing after history reload")
        print("PASS: context failure preserves saved MP4, visible result and durable history")
    }

    private static func checkLanguageSelection() throws {
        for (preferences, expected) in [(["pl-PL"], "pl"), (["es-MX"], "es"), (["de-AT"], "de"), (["en-GB"], "en"), (["ja-JP"], "en"), (["fr-FR", "de-DE"], "de")] {
            try require(AppLanguage.system.resolvedIdentifier(preferredLanguages: preferences) == expected, "language resolution failed")
        }
        try require(AppLanguage.polish.resolvedIdentifier(preferredLanguages: ["en"]) == "pl", "explicit language lost")
        let legacy = try JSONDecoder().decode(AppLanguage.self, from: Data("\"fr\"".utf8))
        try require(legacy == .system, "legacy preference should use automatic fallback")
        print("PASS: PL/EN/ES/DE locale matching, English fallback and legacy preferences")
    }

    private static func checkMultipleWindows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("behavio-windows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("recording.mp4")
        try await makeVideo(at: video)
        func window(_ id: UInt32, _ name: String) -> WindowSource {
            WindowSource(windowID: id, title: name, applicationName: "Test App", applicationBundleIdentifier: "test", processIdentifier: 1, pixelWidth: 640, pixelHeight: 360, frame: CGRect(x: 0, y: 0, width: 640, height: 360), backingScaleFactor: 1)
        }
        let a = window(11, "Window A"), b = window(22, "Window B")
        let timeline = [ContextWindowInterval(window: a, startMs: 0, endMs: 1400), ContextWindowInterval(window: b, startMs: 1800, endMs: 3200), ContextWindowInterval(window: a, startMs: 3600, endMs: 4800)]
        let compilation = try await AgentContextPackageWriter().compile(recordingURL: video, source: .window(a), durationMs: 4800, transcriptStatus: .failed, transcript: [], pointerEvents: [PointerEvent(timeMs: 2000, kind: .click, normalizedX: 0.5, normalizedY: 0.5, windowID: 11)], visualChangeTimesMs: [1600, 3400], windowTimeline: timeline)
        let manifest = compilation.manifest
        try require(manifest.schemaVersion == 3, "multi-window schema missing")
        try require(manifest.windowTimeline == timeline, "return to earlier window lost")
        try require(Set(manifest.visualMoments.compactMap(\.windowID)) == Set([11,22]), "window attribution missing")
        try require(manifest.visualMoments.allSatisfy { $0.pointer == nil }, "stale pointer crossed window boundary")
        try require(manifest.visualMoments.allSatisfy { m in timeline.contains { m.timeMs >= $0.startMs && m.timeMs < $0.endMs && m.windowID == $0.windowID } }, "gap mislabeled as active capture")
        let markdown = try String(contentsOf: compilation.directoryURL.appendingPathComponent("context.md"), encoding: .utf8)
        try require(markdown.contains("## Recorded windows") && markdown.contains("Window A") && markdown.contains("Window B"), "agent-readable window history missing")
        let decoded = try JSONDecoder().decode(AgentContextManifest.self, from: Data(contentsOf: compilation.directoryURL.appendingPathComponent("manifest.json")))
        try require(decoded == manifest, "multi-window manifest roundtrip failed")
        print("PASS: A→B→A attribution, gaps, stale pointer isolation and schema roundtrip")
    }

    private static func checkMomentSelection() throws {
        let transcript = [TranscriptSegment(
            id: "segment-001",
            startMs: 4_000,
            endMs: 6_000,
            text: "Tutaj klikam ten przycisk"
        )]
        let click = PointerEvent(
            id: "pointer-001",
            timeMs: 5_000,
            kind: .click,
            normalizedX: 0.7,
            normalizedY: 0.4
        )
        let dwell = PointerEvent(
            id: "pointer-002",
            timeMs: 8_000,
            kind: .move,
            normalizedX: 0.35,
            normalizedY: 0.65
        )
        let resumedMove = PointerEvent(
            id: "pointer-003",
            timeMs: 10_000,
            kind: .move,
            normalizedX: 0.6,
            normalizedY: 0.6
        )
        let moments = ContextMomentSelector.select(
            durationMs: 120_000,
            transcript: transcript,
            pointerEvents: [click, dwell, resumedMove],
            visualChangeTimesMs: [20_000, 20_200, 40_000]
        )
        try require(moments.count <= 48, "moment limit exceeded")
        try require(moments.contains { $0.reason == .click }, "click moment missing")
        try require(moments.contains { $0.reason == .pointerDwell }, "pointer dwell moment missing")
        try require(
            moments.contains { $0.pointer != nil && abs($0.timeMs - 5_000) <= 500 },
            "speech and pointer evidence were not synchronized"
        )
        let recommended = min(8, moments.count)
        let naiveOneFramePerSecond = 120
        let reduction = 1 - Double(recommended) / Double(naiveOneFramePerSecond)
        try require(reduction >= 0.8, "recommended image reduction below 80%")
    }

    private static func checkContextPackage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("behavio-context-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let recordingDirectory = root.appendingPathComponent("Behavio Context Check", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: false)
        let recordingURL = recordingDirectory.appendingPathComponent("recording.mp4")
        try await makeVideo(at: recordingURL)

        let source = CaptureSource.window(WindowSource(
            windowID: 42,
            title: "Kampania",
            applicationName: "ZODI",
            applicationBundleIdentifier: "one.behavio.zodi",
            processIdentifier: 100,
            pixelWidth: 640,
            pixelHeight: 360,
            frame: CGRect(x: 0, y: 0, width: 640, height: 360),
            backingScaleFactor: 1
        ))
        let transcript = [TranscriptSegment(
            id: "segment-001",
            startMs: 500,
            endMs: 2_000,
            text: "Tutaj klikam ten przycisk",
            words: [
                TranscriptWord(text: "Tutaj", startMs: 500, endMs: 800),
                TranscriptWord(text: "klikam", startMs: 900, endMs: 1_200),
            ]
        )]
        let pointer = PointerEvent(
            id: "pointer-001",
            timeMs: 1_000,
            kind: .click,
            normalizedX: 0.72,
            normalizedY: 0.42
        )
        let compilation = try await AgentContextPackageWriter().compile(
            recordingURL: recordingURL,
            source: source,
            durationMs: 4_000,
            microphone: ContextMicrophone(deviceID: "mic", name: "Studio Mic"),
            transcriptStatus: .complete,
            transcript: transcript,
            pointerEvents: [pointer],
            visualChangeTimesMs: [2_800]
        )

        let contextURL = compilation.directoryURL
        for required in ["context.md", "manifest.json", "transcript.json", "recommended", "on-demand"] {
            try require(
                FileManager.default.fileExists(atPath: contextURL.appendingPathComponent(required).path),
                "missing \(required)"
            )
        }
        try require(compilation.manifest.recommendedInputs.count <= 8, "too many recommended images")
        try require(compilation.manifest.schemaVersion == 2, "unexpected manifest schema")
        try require(compilation.manifest.microphone?.name == "Studio Mic", "microphone metadata missing")
        try require(!compilation.manifest.visualMoments.isEmpty, "no visual moments")
        let manifestText = try String(
            contentsOf: contextURL.appendingPathComponent("manifest.json"),
            encoding: .utf8
        )
        try require(manifestText.contains("\"schema_version\""), "manifest is not snake_case")
        try require(manifestText.contains("\"time_ms\""), "moment timestamp missing")
        let contextText = try String(
            contentsOf: contextURL.appendingPathComponent("context.md"),
            encoding: .utf8
        )
        try require(contextText.contains("## Agent-ready timeline"), "agent timeline missing")
        try require(contextText.contains("Microphone: Studio Mic"), "microphone missing from context")

        let decodedManifest = try JSONDecoder().decode(
            AgentContextManifest.self,
            from: Data(contentsOf: contextURL.appendingPathComponent("manifest.json"))
        )
        try require(decodedManifest == compilation.manifest, "manifest round trip changed data")
        let recommended = Set(decodedManifest.recommendedInputs)
        for moment in decodedManifest.visualMoments {
            try require(!moment.path.hasPrefix("/"), "absolute image path escaped package")
            try require(!moment.path.contains(".."), "relative image path escaped package")
            let imageURL = contextURL.appendingPathComponent(moment.path)
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                throw CheckFailure("unreadable image at \(moment.path)")
            }
            let expectedLimit = recommended.contains(moment.id) && moment.reason == .click ? 768 : 1_280
            try require(max(width, height) <= expectedLimit, "image dimensions exceed limit")
        }

        let descendants = try FileManager.default.subpathsOfDirectory(atPath: contextURL.path)
        let forbidden = Set(["mp4", "mov", "m4a", "wav", "aac", "mp3"])
        try require(
            descendants.allSatisfy { !forbidden.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) },
            "audio or video leaked into context folder"
        )
        try require(
            !FileManager.default.fileExists(atPath: contextURL.appendingPathComponent("recording.mp4").path),
            "source recording leaked into context folder"
        )
    }

    private static func checkRecordingFolders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("behavio-storage-check-\(UUID().uuidString)", isDirectory: true)
        let original = root.appendingPathComponent("original", isDirectory: true)
        let selected = root.appendingPathComponent("selected", isDirectory: true)
        let suite = "one.behavio.storage-check.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        for folder in [original, selected] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        func entry(in folder: URL, date: Date) throws -> RecordingHistoryEntry {
            let directory = folder.appendingPathComponent("Behavio Context Test", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let file = directory.appendingPathComponent("recording.mp4")
            try Data("history fixture".utf8).write(to: file)
            return RecordingHistoryEntry(id: UUID(), fileURL: file, recordedAt: date)
        }
        let old = try entry(in: original, date: Date(timeIntervalSince1970: 1))
        let library = RecordingLibrary(defaults: UserDefaults(suiteName: suite)!, defaultDirectory: original)
        try await library.save(RecordingHistorySnapshot(recordings: [old], selectedRecordingID: old.id))
        try await library.selectDirectory(selected)
        let destination = try await library.recordingDirectory()
        try require(destination.standardizedFileURL == selected.standardizedFileURL, "destination not changed")
        let recent = try entry(in: destination, date: Date(timeIntervalSince1970: 2))
        try await library.save(RecordingHistorySnapshot(recordings: [old, recent], selectedRecordingID: old.id))
        let reopened = RecordingLibrary(defaults: UserDefaults(suiteName: suite)!, defaultDirectory: original)
        let restoredDestination = try await reopened.recordingDirectory()
        try require(restoredDestination.standardizedFileURL == selected.standardizedFileURL, "destination lost on restart")
        let history = try await reopened.load()
        try require(Set(history.recordings.map(\.id)) == Set([old.id, recent.id]), "old or new history missing")
        try require(history.selectedRecordingID == old.id, "selected recording lost on restart")
        try require(FileManager.default.fileExists(atPath: old.fileURL.path), "old recording moved or deleted")
        do {
            try await reopened.selectDirectory(recent.fileURL)
            throw CheckFailure("accepted a file as a recording folder")
        } catch is CocoaError { }
        let afterFailure = try await reopened.recordingDirectory()
        try require(afterFailure.standardizedFileURL == selected.standardizedFileURL, "invalid choice changed destination")
        try await reopened.useDefaultDirectory()
        let restoredDefault = try await reopened.recordingDirectory()
        try require(restoredDefault == original, "default not restored")
        try await reopened.delete(recent)
        let remaining = try await reopened.load()
        try require(remaining.recordings.map(\.id) == [old.id], "deleting newer recording affected older folder")
        print("PASS: selected recording folder, restart persistence, merged history, default restore, safe deletion")
    }

    private static func checkDelayedVideo() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("behavio-timing-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordingURL = root.appendingPathComponent("recording.mp4")
        try await makeVideo(at: recordingURL, videoStartMs: 750)
        let source = CaptureSource.window(WindowSource(
            windowID: 42, title: "Timing fixture", applicationName: "Fixture",
            applicationBundleIdentifier: "one.behavio.fixture", processIdentifier: 100,
            pixelWidth: 640, pixelHeight: 360,
            frame: CGRect(x: 0, y: 0, width: 640, height: 360), backingScaleFactor: 1
        ))
        let result = try await AgentContextPackageWriter().compile(
            recordingURL: recordingURL, source: source, durationMs: 6_000,
            transcriptStatus: .failed, transcript: [], pointerEvents: [],
            visualChangeTimesMs: [2_100]
        )
        try require(!result.manifest.visualMoments.isEmpty, "delayed video has no moments")
        try require(result.manifest.visualMoments.first?.timeMs == 750, "first frame not recovered")
        try require(result.manifest.visualMoments.contains { $0.timeMs == 1_750 }, "sparse gap did not use preceding frame")
        try require(result.manifest.visualMoments.last?.timeMs == 5_250, "last frame not recovered")
        for moment in result.manifest.visualMoments {
            try require(moment.timeMs >= 750, "timestamp precedes the first video frame")
            let imageURL = result.directoryURL.appendingPathComponent(moment.path)
            guard let image = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else {
                throw CheckFailure("timing fixture image cannot be decoded")
            }
        }
        print("PASS: delayed first frame, sparse frames, and final frame extraction")
    }

    private static func makeVideo(at url: URL, videoStartMs: Int = 0) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 640,
                AVVideoHeightKey: 360,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360,
            ]
        )
        guard writer.canAdd(input) else { throw CheckFailure("cannot add video input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CheckFailure("cannot start video writer") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pixelBuffer = makePixelBuffer(frame: frame) else {
                throw CheckFailure("cannot create pixel buffer")
            }
            let time = CMTime(value: CMTimeValue(videoStartMs + frame * 500), timescale: 1_000)
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw writer.error ?? CheckFailure("cannot append video frame")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CheckFailure("cannot finish video")
        }
    }

    private static func makePixelBuffer(frame: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            640,
            360,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let blue = UInt8(40 + frame * 12)
        for y in 0..<360 {
            for x in 0..<640 {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = blue
                pixels[offset + 1] = UInt8(80 + (x / 8) % 100)
                pixels[offset + 2] = UInt8(100 + (y / 6) % 100)
                pixels[offset + 3] = 255
            }
        }
        return buffer
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct CheckCatalog: CaptureSourceCatalog {
    let source: CaptureSource
    func sources() async throws -> [CaptureSource] { [source] }
}
private struct CheckAuthorization: CaptureAuthorization {
    func requestCameraAccess() async -> Bool { true }
    func requestMicrophoneAccess() async -> Bool { true }
    func requestSystemAudioAccess(for source: CaptureSource) async -> Bool { true }
}
private actor CheckPreferences: PreferencesStore {
    func load() async -> PreferencesSnapshot { PreferencesSnapshot(capturesMicrophone: false) }
    func save(_ snapshot: PreferencesSnapshot) async {}
}
private struct PartialSuccessPipeline: RecordingPipeline {
    let video: URL
    func start(configuration: RecordingConfiguration) async throws -> AsyncStream<RecordingPipelineEvent> { AsyncStream { $0.finish() } }
    func stop() async throws -> RecordingArtifacts {
        var artifacts = RecordingArtifacts(recordingURL: video)
        artifacts.contextFailure = "Fixture: frame extraction failed"
        return artifacts
    }
    func cancel() async {}
}
