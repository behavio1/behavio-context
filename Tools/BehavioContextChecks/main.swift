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
            windowID: 1,
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
            visualChangeTimesMs: visualChanges
        )
        print("PASS: reprocessed \(compilation.directoryURL.path)")
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

    private static func makeVideo(at url: URL) async throws {
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
            let time = CMTime(value: CMTimeValue(frame), timescale: 2)
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
