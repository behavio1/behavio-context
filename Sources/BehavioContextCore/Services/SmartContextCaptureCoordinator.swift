@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import Speech

public enum SmartContextCoordinatorError: Error, LocalizedError {
    case activeWindowRequired
    case speechPermissionDenied
    case polishRecognitionUnavailable
    case onDeviceRecognitionUnavailable

    public var errorDescription: String? {
        switch self {
        case .activeWindowRequired:
            "Choose an active window before recording."
        case .speechPermissionDenied:
            "Speech Recognition permission is required for local transcription."
        case .polishRecognitionUnavailable:
            "Polish speech recognition is unavailable on this Mac."
        case .onDeviceRecognitionUnavailable:
            "The Polish on-device speech model is unavailable."
        }
    }
}

public actor SmartContextCaptureCoordinator {
    private let writer: AgentContextPackageWriter
    private var transcriber: LocalPolishTranscriber?
    private var source: CaptureSource?
    private var microphone: ContextMicrophone?
    private var pointerEvents: [PointerEvent] = []
    private var visualChangeTimesMs: [Int] = []
    private var startedAt: Date?
    private var startedHostTime = 0.0
    private var windowClosed = false
    private var windows: [(window: WindowSource, start: Double, end: Double)] = []
    private var transcriptStatus: TranscriptStatus = .failed
    private var update: (@Sendable (RecordingPipelineEvent) -> Void)?

    public init(writer: AgentContextPackageWriter = AgentContextPackageWriter()) {
        self.writer = writer
    }

    public func start(
        source: CaptureSource,
        microphone: ContextMicrophone? = nil,
        update: @escaping @Sendable (RecordingPipelineEvent) -> Void
    ) async throws {
        guard case .window = source else {
            throw SmartContextCoordinatorError.activeWindowRequired
        }
        await cancel()
        self.source = source
        self.microphone = microphone
        self.update = update
        startedAt = Date()
        startedHostTime = ProcessInfo.processInfo.systemUptime
        pointerEvents = []
        visualChangeTimesMs = []
        transcriptStatus = .failed

        let transcriber = LocalPolishTranscriber { transcript, isFinal in
            update(.transcriptChanged(text: transcript, isFinal: isFinal))
        }
        do {
            try await transcriber.start()
            self.transcriber = transcriber
            transcriptStatus = .partial
        } catch {
            self.transcriber = nil
            transcriptStatus = .failed
            update(.transcriptionUnavailable(message: error.localizedDescription))
        }
    }

    public nonisolated func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        Task { await self.transcriber?.append(sampleBuffer) }
    }

    public func recordWindowFrame(window: WindowSource, hostTime: Double) {
        guard startedAt != nil else { return }
        if let last = windows.last, last.window == window, !windowClosed {
            windows[windows.count - 1].end = max(last.end, hostTime)
        } else {
            windows.append((window, hostTime, hostTime))
            windowClosed = false
        }
    }

    public func closeWindowCapture() {
        if !windowClosed, !windows.isEmpty { windows[windows.count - 1].end = ProcessInfo.processInfo.systemUptime }
        windowClosed = true
    }

    public func recordPointerEvent(_ event: PointerEvent) {
        guard startedAt != nil else { return }
        if event.kind == .move,
           let last = pointerEvents.last,
           last.kind == .move,
           event.timeMs - last.timeMs < 80 {
            pointerEvents[pointerEvents.count - 1] = event
        } else {
            pointerEvents.append(event)
        }
    }

    public func recordVisualChange(timeMs: Int) {
        guard startedAt != nil,
              visualChangeTimesMs.last.map({ timeMs - $0 >= 700 }) ?? true else { return }
        visualChangeTimesMs.append(max(0, timeMs))
    }

    public func setMicrophone(_ microphone: ContextMicrophone?) {
        self.microphone = microphone
    }

    public func stop(recordingURL: URL, mediaStartHostTime: Double? = nil) async throws -> AgentContextCompilation {
        guard let source else {
            throw SmartContextCoordinatorError.activeWindowRequired
        }
        update?(.compilationProgress(message: "Finalizing transcript…"))
        var segments = await transcriber?.stop() ?? []
        if segments.isEmpty, microphone != nil {
            update?(.compilationProgress(message: "Recovering the transcript locally…"))
            segments = await RecordedPolishTranscriber().transcribe(recordingURL: recordingURL)
        }
        if !segments.isEmpty {
            transcriptStatus = .complete
        } else {
            transcriptStatus = .failed
        }
        let origin = mediaStartHostTime ?? startedHostTime
        let timeline = windows.map { ContextWindowInterval(window: $0.window, startMs: max(0, Int(($0.start - origin) * 1000)), endMs: max(0, Int(($0.end - origin) * 1000))) }
        let mappedPointers = pointerEvents.map { PointerEvent(id: $0.id, timeMs: max(0, $0.timeMs - Int(origin * 1000)), kind: $0.kind, normalizedX: $0.normalizedX, normalizedY: $0.normalizedY, windowID: $0.windowID) }
        let offset = Int((startedHostTime - origin) * 1000)
        segments = segments.map { TranscriptSegment(id: $0.id, startMs: max(0, $0.startMs + offset), endMs: max(0, $0.endMs + offset), text: $0.text, words: $0.words.map { TranscriptWord(text: $0.text, startMs: max(0, $0.startMs + offset), endMs: max(0, $0.endMs + offset)) }) }
        let durationMs = max(
            1,
            Int((startedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1_000)
        )
        update?(.compilationProgress(message: "Selecting key moments…"))
        let compilation = try await writer.compile(
            recordingURL: recordingURL,
            source: source,
            durationMs: durationMs,
            microphone: microphone,
            transcriptStatus: transcriptStatus,
            transcript: segments,
            pointerEvents: mappedPointers,
            visualChangeTimesMs: visualChangeTimesMs,
            windowTimeline: timeline
        )
        update?(.compilationProgress(message: "Context ready"))
        clear()
        return compilation
    }

    public func cancel() async {
        await transcriber?.cancel()
        clear()
    }

    private func clear() {
        transcriber = nil
        source = nil
        microphone = nil
        pointerEvents = []
        visualChangeTimesMs = []
        startedAt = nil
        windows = []
        update = nil
        transcriptStatus = .failed
    }
}

private final class LocalPolishTranscriber: @unchecked Sendable {
    private let queue = DispatchQueue(label: "one.behavio.context.transcription")
    private let lock = NSLock()
    private let update: @Sendable (String, Bool) -> Void
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestSegments: [TranscriptSegment] = []
    private var receivedFinalResult = false
    private var hasStopped = false

    init(update: @escaping @Sendable (String, Bool) -> Void) {
        self.update = update
    }

    func start() async throws {
        let authorization = await Self.authorizationStatus()
        guard authorization == .authorized else {
            throw SmartContextCoordinatorError.speechPermissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl_PL")),
              recognizer.isAvailable else {
            throw SmartContextCoordinatorError.polishRecognitionUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SmartContextCoordinatorError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation

        lock.withLock {
            self.recognizer = recognizer
            self.request = request
            hasStopped = false
            receivedFinalResult = false
            latestSegments = []
        }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.handle(result)
            }
            if error != nil {
                self.lock.withLock { self.hasStopped = true }
            }
        }
        lock.withLock { self.task = task }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let currentRequest = lock.withLock { hasStopped ? nil : request }
        currentRequest?.appendAudioSampleBuffer(sampleBuffer)
    }

    func stop() async -> [TranscriptSegment] {
        lock.withLock { request?.endAudio() }
        for _ in 0..<40 {
            if lock.withLock({ receivedFinalResult || hasStopped }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let snapshot = lock.withLock { () -> [TranscriptSegment] in
            task?.cancel()
            task = nil
            request = nil
            recognizer = nil
            hasStopped = true
            return latestSegments
        }
        return snapshot
    }

    func cancel() async {
        lock.withLock {
            request?.endAudio()
            task?.cancel()
            task = nil
            request = nil
            recognizer = nil
            hasStopped = true
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = TranscriptResultConverter.segments(from: result.bestTranscription)
        lock.withLock {
            latestSegments = segments
            if result.isFinal {
                receivedFinalResult = true
                hasStopped = true
            }
        }
        update(text, result.isFinal)
    }

    private static func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private final class RecordedPolishTranscriber: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<[TranscriptSegment], Never>?
    private var latestSegments: [TranscriptSegment] = []

    func transcribe(recordingURL: URL) async -> [TranscriptSegment] {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl_PL")),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: recordingURL)
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.taskHint = .dictation
            lock.withLock {
                self.recognizer = recognizer
                self.continuation = continuation
                latestSegments = []
            }
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let segments = TranscriptResultConverter.segments(from: result.bestTranscription)
                    lock.withLock { latestSegments = segments }
                    if result.isFinal {
                        finish(with: segments)
                    }
                }
                if error != nil {
                    finish(with: lock.withLock { latestSegments })
                }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard !Task.isCancelled, let self else { return }
                finish(with: lock.withLock { latestSegments })
            }
        }
    }

    private func finish(with segments: [TranscriptSegment]) {
        let continuation = lock.withLock { () -> CheckedContinuation<[TranscriptSegment], Never>? in
            guard let continuation = self.continuation else { return nil }
            self.continuation = nil
            return continuation
        }
        guard let continuation else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recognizer = nil
        continuation.resume(returning: segments)
    }
}

private enum TranscriptResultConverter {
    static func segments(from transcription: SFTranscription) -> [TranscriptSegment] {
        let words = transcription.segments.map { segment in
            TranscriptWord(
                text: segment.substring.trimmingCharacters(in: .whitespacesAndNewlines),
                startMs: max(0, Int(segment.timestamp * 1_000)),
                endMs: max(0, Int((segment.timestamp + segment.duration) * 1_000))
            )
        }.filter { !$0.text.isEmpty }
        guard !words.isEmpty else { return [] }

        var groups: [[TranscriptWord]] = []
        for word in words {
            if let last = groups.last?.last,
               word.startMs - last.endMs <= 1_100,
               word.endMs - (groups.last?.first?.startMs ?? word.startMs) <= 10_000 {
                groups[groups.count - 1].append(word)
            } else {
                groups.append([word])
            }
        }
        return groups.enumerated().map { index, group in
            TranscriptSegment(
                id: String(format: "segment-%03d", index + 1),
                startMs: group.first?.startMs ?? 0,
                endMs: group.last?.endMs ?? 0,
                text: clean(group.map(\.text).joined(separator: " ")),
                words: group
            )
        }
    }

    private static func clean(_ text: String) -> String {
        [",", ".", "!", "?", ":", ";"].reduce(text) { value, punctuation in
            value.replacingOccurrences(of: " \(punctuation)", with: punctuation)
        }
    }
}

final class VisualChangeSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var firstTimestamp: CMTime?
    private var lastSampleTimestamp: CMTime?
    private var lastSignature: [UInt8]?

    func reset() {
        lock.withLock {
            firstTimestamp = nil
            lastSampleTimestamp = nil
            lastSignature = nil
        }
    }

    func process(_ sampleBuffer: CMSampleBuffer) -> Int? {
        lock.withLock {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstTimestamp == nil { firstTimestamp = timestamp }
            if let lastSampleTimestamp,
               CMTimeGetSeconds(timestamp - lastSampleTimestamp) < 0.5 {
                return nil
            }
            lastSampleTimestamp = timestamp
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
                return nil
            }
            let signature = Self.signature(pixelBuffer)
            defer { lastSignature = signature }
            guard let previous = lastSignature, previous.count == signature.count else { return 0 }
            let difference = zip(previous, signature).reduce(0) {
                $0 + abs(Int($1.0) - Int($1.1))
            } / signature.count
            guard difference >= 16, let firstTimestamp else { return nil }
            return max(0, Int(CMTimeGetSeconds(timestamp - firstTimestamp) * 1_000))
        }
    }

    private static func signature(_ pixelBuffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var values: [UInt8] = []
        values.reserveCapacity(144)
        for gridY in 0..<9 {
            let y = min(height - 1, max(0, (gridY * height + height / 2) / 9))
            for gridX in 0..<16 {
                let x = min(width - 1, max(0, (gridX * width + width / 2) / 16))
                let offset = y * bytesPerRow + x * 4
                let blue = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let red = Int(pixels[offset + 2])
                values.append(UInt8((red * 30 + green * 59 + blue * 11) / 100))
            }
        }
        return values
    }
}
