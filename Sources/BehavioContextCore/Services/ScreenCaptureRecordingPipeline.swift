@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

public actor ScreenCaptureRecordingPipeline: RecordingPipeline {
    private let logger = Logger(
        subsystem: "one.behavio.context",
        category: "capture"
    )
    private let recorder: LocalMediaRecorder
    private let bundleIdentifier: String
    private let contextCapture: SmartContextCaptureCoordinator?
    private let visualChangeSampler = VisualChangeSampler()
    private var captureStream: SCStream?
    private var outputBridge: ScreenCaptureOutputBridge?
    private var eventContinuation: AsyncStream<RecordingPipelineEvent>.Continuation?
    private var sampleForwarder: MediaSampleForwarder?
    private var microphoneCapture: MicrophoneCaptureSource?
    private var activeMicrophoneID: String?
    private var streamConfiguration: SCStreamConfiguration?
    private var captureGeneration = UUID()

    public init(
        recorder: LocalMediaRecorder = LocalMediaRecorder(),
        bundleIdentifier: String = "one.behavio.context",
        contextCapture: SmartContextCaptureCoordinator? = nil
    ) {
        self.recorder = recorder
        self.bundleIdentifier = bundleIdentifier
        self.contextCapture = contextCapture
    }

    public func start(configuration: RecordingConfiguration) async throws -> AsyncStream<RecordingPipelineEvent> {
        await cancel()
        try Task.checkCancellation()

        let events = AsyncStream<RecordingPipelineEvent> { continuation in
            self.eventContinuation = continuation
        }
        visualChangeSampler.reset()
        let resolvedMicrophone = configuration.capturesMicrophone
            ? CaptureDeviceCatalog.microphone(withID: configuration.microphoneDeviceID)
            : nil
        let contextMicrophone = resolvedMicrophone.map {
            ContextMicrophone(deviceID: $0.uniqueID, name: $0.localizedName)
        }
        try await contextCapture?.start(
            source: configuration.source,
            microphone: contextMicrophone,
            speech: configuration.speech
        ) { [weak self] event in
            Task { await self?.eventContinuation?.yield(event) }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        try Task.checkCancellation()
        let resolvedTarget = try ScreenCaptureKitContentFilterFactory.resolve(
            for: configuration.source,
            in: content,
            excludingBundleIdentifier: bundleIdentifier
        )
        let filter = resolvedTarget.filter
        let profile = OutputProfile.make(
            pixelWidth: resolvedTarget.pixelWidth,
            pixelHeight: resolvedTarget.pixelHeight
        )
        let sourceID = configuration.source.id
        logger.info(
            "Preparing \(sourceID.kind.rawValue, privacy: .public) \(sourceID.rawValue, privacy: .public) at \(profile.width, privacy: .public)x\(profile.height, privacy: .public)"
        )
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = profile.width
        streamConfiguration.height = profile.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfiguration.queueDepth = 5
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = true
        streamConfiguration.scalesToFit = true
        self.streamConfiguration = streamConfiguration
        streamConfiguration.capturesAudio = false
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2

        let sampleForwarder = MediaSampleForwarder(
            sink: recorder,
            microphoneTrack: 0
        )
        self.sampleForwarder = sampleForwarder

        do {
            try await recorder.start(
                profile: profile,
                capturesAudio: configuration.capturesMicrophone
            )
            try Task.checkCancellation()

            if configuration.capturesMicrophone {
                let microphoneCapture = makeMicrophoneCapture(sampleForwarder: sampleForwarder)
                try await microphoneCapture.start(
                    microphoneID: resolvedMicrophone?.uniqueID
                )
                try Task.checkCancellation()
                self.microphoneCapture = microphoneCapture
                activeMicrophoneID = resolvedMicrophone?.uniqueID
                if let resolvedMicrophone {
                    eventContinuation?.yield(.microphoneChanged(
                        deviceID: resolvedMicrophone.uniqueID,
                        name: resolvedMicrophone.localizedName
                    ))
                }
            }

            let outputBridge = ScreenCaptureOutputBridge(
                window: configuration.source.windowSource,
                onSample: { [visualChangeSampler, contextCapture] sampleBuffer, outputType, window in
                    if outputType == .screen, let window {
                        let host = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)
                        Task { await contextCapture?.recordWindowFrame(window: window, hostTime: host) }
                    }
                    sampleForwarder.yield(sampleBuffer, outputType: outputType)
                    if outputType == .screen,
                       let timeMs = visualChangeSampler.process(sampleBuffer) {
                        Task { await contextCapture?.recordVisualChange(timeMs: timeMs) }
                    }
                },
                onFatalError: { [weak self] error in
                    Task {
                        await self?.eventContinuation?.yield(.fatal(message: error.localizedDescription))
                    }
                }
            )
            let captureStream = SCStream(
                filter: filter,
                configuration: streamConfiguration,
                delegate: outputBridge
            )
            try captureStream.addStreamOutput(
                outputBridge,
                type: .screen,
                sampleHandlerQueue: outputBridge.videoQueue
            )
            self.outputBridge = outputBridge
            self.captureStream = captureStream
            try await captureStream.startCapture()
            try Task.checkCancellation()
            logger.info("ScreenCaptureKit capture started")
            return events
        } catch {
            await cancel()
            throw error
        }
    }

    public func followWindow(_ source: CaptureSource?) async throws {
        let generation = captureGeneration
        outputBridge?.invalidate()
        if let captureStream { try? await captureStream.stopCapture() }
        self.captureStream = nil
        self.outputBridge = nil
        await contextCapture?.closeWindowCapture()
        guard let source, let configuration = streamConfiguration,
              let forwarder = sampleForwarder, generation == captureGeneration else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard generation == captureGeneration else { return }
        let target = try ScreenCaptureKitContentFilterFactory.resolve(for: source, in: content, excludingBundleIdentifier: bundleIdentifier)
        let bridge = ScreenCaptureOutputBridge(window: source.windowSource, onSample: { [contextCapture] sample, type, window in
            forwarder.yield(sample, outputType: type)
            if type == .screen, let window {
                let host = CMTimeGetSeconds(sample.presentationTimeStamp)
                Task { await contextCapture?.recordWindowFrame(window: window, hostTime: host) }
            }
        }, onFatalError: { [weak self] error in
            Task { await self?.eventContinuation?.yield(.fatal(message: error.localizedDescription)) }
        })
        let stream = SCStream(filter: target.filter, configuration: configuration, delegate: bridge)
        try stream.addStreamOutput(bridge, type: .screen, sampleHandlerQueue: bridge.videoQueue)
        guard generation == captureGeneration else { return }
        captureStream = stream
        outputBridge = bridge
        try await stream.startCapture()
        if generation != captureGeneration { bridge.invalidate(); try? await stream.stopCapture() }
    }

    public func refreshWindowMetadata(_ window: WindowSource) {
        outputBridge?.refreshWindowMetadata(window)
    }

    public func changeSpeech(_ settings: SpeechSettings) async {
        await contextCapture?.changeSpeech(settings)
    }

    public func selectMicrophoneDevice(_ deviceID: String?) async throws {
        guard let microphoneCapture else {
            throw RecordingPipelineControlError.microphoneNotActive
        }
        guard let selected = CaptureDeviceCatalog.microphone(withID: deviceID) else {
            throw MicrophoneCaptureError.microphoneUnavailable
        }
        guard selected.uniqueID != activeMicrophoneID else { return }

        let previousID = activeMicrophoneID
        await microphoneCapture.stop()
        do {
            try await microphoneCapture.start(microphoneID: selected.uniqueID)
            activeMicrophoneID = selected.uniqueID
            let contextMicrophone = ContextMicrophone(
                deviceID: selected.uniqueID,
                name: selected.localizedName
            )
            await contextCapture?.setMicrophone(contextMicrophone)
            eventContinuation?.yield(.microphoneChanged(
                deviceID: selected.uniqueID,
                name: selected.localizedName
            ))
            logger.info("Microphone changed to \(selected.localizedName, privacy: .public)")
        } catch {
            if let previousID {
                try? await microphoneCapture.start(microphoneID: previousID)
                activeMicrophoneID = previousID
            }
            throw error
        }
    }

    public func stop() async throws -> RecordingArtifacts {
        do {
            try await stopCaptureSources()
        } catch {
            logger.warning("Capture source did not stop cleanly: \(error.localizedDescription, privacy: .public)")
        }
        await contextCapture?.closeWindowCapture()
        let artifacts = try await recorder.finish()
        var result = artifacts
        do {
            let context = try await contextCapture?.stop(recordingURL: artifacts.recordingURL, mediaStartHostTime: artifacts.mediaStartHostTime)
            result = RecordingArtifacts(recordingURL: artifacts.recordingURL, contextDirectoryURL: context?.directoryURL)
        } catch {
            // A finalized video remains a successful, visible library entry.
            result.contextFailure = error.localizedDescription
            await contextCapture?.cancel()
        }
        logger.info("Recording pipeline stopped")
        eventContinuation?.finish()
        eventContinuation = nil
        return result
    }

    public func cancel() async {
        try? await stopCaptureSources()
        await recorder.cancel()
        await contextCapture?.cancel()
        logger.info("Recording pipeline cancelled")
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func stopCaptureSources() async throws {
        captureGeneration = UUID()
        streamConfiguration = nil
        outputBridge?.invalidate()
        var stopError: Error?
        if let captureStream {
            do {
                try await captureStream.stopCapture()
            } catch {
                stopError = error
            }
        }
        captureStream = nil
        outputBridge = nil

        let microphoneCapture = self.microphoneCapture
        self.microphoneCapture = nil
        await microphoneCapture?.stop()
        activeMicrophoneID = nil

        let sampleForwarder = self.sampleForwarder
        self.sampleForwarder = nil
        await sampleForwarder?.stop()

        if let stopError {
            throw stopError
        }
    }

    private func makeMicrophoneCapture(
        sampleForwarder: MediaSampleForwarder
    ) -> MicrophoneCaptureSource {
        MicrophoneCaptureSource(
            onSample: { [contextCapture] sampleBuffer in
                sampleForwarder.yieldMicrophone(sampleBuffer)
                contextCapture?.appendMicrophone(sampleBuffer)
            },
            onLevel: { [weak self] level in
                Task { await self?.eventContinuation?.yield(.microphoneLevel(level)) }
            }
        )
    }
}

struct ForwardedSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

final class MediaSampleForwarder: @unchecked Sendable {
    private let videoContinuation: AsyncStream<ForwardedSample>.Continuation
    private let microphoneContinuation: AsyncStream<ForwardedSample>.Continuation
    private let tasks: [Task<Void, Never>]
    private let lock = NSLock()
    private var acceptsSamples = true

    init(
        sink: any MediaSampleSink,
        microphoneTrack: UInt8 = 0
    ) {
        let videoSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        let microphoneSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        videoContinuation = videoSamples.continuation
        microphoneContinuation = microphoneSamples.continuation
        tasks = [
            Task {
                for await sample in videoSamples.stream {
                    guard !Task.isCancelled else { break }
                    await sink.appendVideo(sample.buffer, track: 0)
                }
            },
            Task {
                for await sample in microphoneSamples.stream {
                    guard !Task.isCancelled else { break }
                    await sink.appendAudio(sample.buffer, track: microphoneTrack)
                }
            },
        ]
    }

    func yield(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard lock.withLock({ acceptsSamples }) else { return }
        let sample = ForwardedSample(buffer: sampleBuffer)
        switch outputType {
        case .screen:
            videoContinuation.yield(sample)
        case .audio:
            break
        case .microphone:
            microphoneContinuation.yield(sample)
        @unknown default:
            break
        }
    }

    func yieldMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard lock.withLock({ acceptsSamples }) else { return }
        microphoneContinuation.yield(ForwardedSample(buffer: sampleBuffer))
    }

    func stop() async {
        let shouldStop = lock.withLock {
            guard acceptsSamples else { return false }
            acceptsSamples = false
            return true
        }
        guard shouldStop else { return }

        videoContinuation.finish()
        microphoneContinuation.finish()
        for task in tasks {
            task.cancel()
        }
        for task in tasks {
            await task.value
        }
    }
}

private enum MicrophoneCaptureError: Error, LocalizedError {
    case microphoneUnavailable
    case cannotAddMicrophone
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "The selected microphone is unavailable."
        case .cannotAddMicrophone:
            "The selected microphone could not be added to the capture session."
        case .cannotAddOutput:
            "Microphone audio output could not be configured."
        }
    }
}

private final class MicrophoneCaptureSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "one.behavio.context.capture.microphone.session",
        qos: .userInitiated
    )
    private let sampleQueue = DispatchQueue(
        label: "one.behavio.context.capture.microphone.samples",
        qos: .userInteractive
    )
    private let onSample: @Sendable (CMSampleBuffer) -> Void
    private let onLevel: @Sendable (Double) -> Void
    private var audioOutput: AVCaptureAudioDataOutput?
    private var lastLevelUpdate = Date.distantPast

    init(
        onSample: @escaping @Sendable (CMSampleBuffer) -> Void,
        onLevel: @escaping @Sendable (Double) -> Void
    ) {
        self.onSample = onSample
        self.onLevel = onLevel
    }

    func start(microphoneID: String?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    guard let microphone = CaptureDeviceCatalog.microphone(withID: microphoneID) else {
                        throw MicrophoneCaptureError.microphoneUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: microphone)
                    let output = AVCaptureAudioDataOutput()
                    output.setSampleBufferDelegate(self, queue: sampleQueue)

                    session.beginConfiguration()
                    session.inputs.forEach(session.removeInput)
                    session.outputs.forEach(session.removeOutput)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw MicrophoneCaptureError.cannotAddMicrophone
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw MicrophoneCaptureError.cannotAddOutput
                    }
                    session.addOutput(output)
                    session.commitConfiguration()
                    audioOutput = output
                    session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                if session.isRunning {
                    session.stopRunning()
                }
                audioOutput = nil
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if Date().timeIntervalSince(lastLevelUpdate) >= 0.08 {
            let decibels = connection.audioChannels.first?.averagePowerLevel ?? -60
            let normalized = min(1, max(0, Double(decibels + 60) / 60))
            onLevel(normalized)
            lastLevelUpdate = Date()
        }
        guard let synchronizationClock = session.synchronizationClock else {
            onSample(sampleBuffer)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let synchronizedSample = copySampleBuffer(
            sampleBuffer,
            convertingTimestampsWith: {
                CMSyncConvertTime($0, from: synchronizationClock, to: hostClock)
            }
        ) ?? sampleBuffer
        onSample(synchronizedSample)
    }
}

func copySampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    convertingTimestampsWith convert: (CMTime) -> CMTime
) -> CMSampleBuffer? {
    var timingEntryCount = 0
    guard CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer,
        entryCount: 0,
        arrayToFill: nil,
        entriesNeededOut: &timingEntryCount
    ) == noErr, timingEntryCount > 0 else {
        return nil
    }

    var timingEntries = Array(
        repeating: CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        ),
        count: timingEntryCount
    )
    guard CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer,
        entryCount: timingEntryCount,
        arrayToFill: &timingEntries,
        entriesNeededOut: nil
    ) == noErr else {
        return nil
    }

    for index in timingEntries.indices {
        if timingEntries[index].presentationTimeStamp.isValid {
            timingEntries[index].presentationTimeStamp = convert(
                timingEntries[index].presentationTimeStamp
            )
        }
        if timingEntries[index].decodeTimeStamp.isValid {
            timingEntries[index].decodeTimeStamp = convert(
                timingEntries[index].decodeTimeStamp
            )
        }
    }

    var synchronizedSample: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
        allocator: kCFAllocatorDefault,
        sampleBuffer: sampleBuffer,
        sampleTimingEntryCount: timingEntryCount,
        sampleTimingArray: &timingEntries,
        sampleBufferOut: &synchronizedSample
    )
    guard status == noErr else { return nil }
    return synchronizedSample
}

public enum PipelineError: Error, LocalizedError, Sendable {
    case selectedSourceUnavailable

    public var errorDescription: String? {
        switch self {
        case .selectedSourceUnavailable:
            "The selected screen or window is no longer available. Choose another source and try again."
        }
    }
}

func isCompleteScreenCaptureFrame(
    _ attachments: [SCStreamFrameInfo: Any]?
) -> Bool {
    guard let rawStatus = attachments?[.status] as? Int,
          let status = SCFrameStatus(rawValue: rawStatus) else {
        return false
    }
    return status == .complete
}

private final class ScreenCaptureOutputBridge: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let videoQueue = DispatchQueue(label: "one.behavio.context.capture.video", qos: .userInteractive)
    private let onSample: @Sendable (CMSampleBuffer, SCStreamOutputType, WindowSource?) -> Void
    private var window: WindowSource?
    private let onFatalError: @Sendable (Error) -> Void
    private let lock = NSLock()
    private var acceptsCallbacks = true

    init(
        window: WindowSource?,
        onSample: @escaping @Sendable (CMSampleBuffer, SCStreamOutputType, WindowSource?) -> Void,
        onFatalError: @escaping @Sendable (Error) -> Void
    ) {
        self.onSample = onSample
        self.onFatalError = onFatalError
        self.window = window
    }

    func refreshWindowMetadata(_ updated: WindowSource) {
        lock.withLock {
            guard window?.windowID == updated.windowID else { return }
            window = updated
        }
    }

    func invalidate() {
        lock.withLock {
            acceptsCallbacks = false
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid, lock.withLock({ acceptsCallbacks }) else { return }
        if outputType == .screen {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]]
            guard isCompleteScreenCaptureFrame(attachments?.first) else { return }
        }
        guard let synchronizationClock = stream.synchronizationClock else {
            onSample(sampleBuffer, outputType, lock.withLock { window })
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let synchronizedSample = copySampleBuffer(
            sampleBuffer,
            convertingTimestampsWith: {
                CMSyncConvertTime($0, from: synchronizationClock, to: hostClock)
            }
        ) ?? sampleBuffer
        onSample(synchronizedSample, outputType, lock.withLock { window })
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard lock.withLock({ acceptsCallbacks }) else { return }
        onFatalError(error)
    }
}
