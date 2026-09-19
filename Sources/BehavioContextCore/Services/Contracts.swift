@preconcurrency import CoreMedia
import Foundation

public protocol CaptureSourceCatalog: Sendable {
    func sources() async throws -> [CaptureSource]
    func hasAccess() async -> Bool
    func requestAccess() async -> Bool
}

public protocol CaptureAuthorization: Sendable {
    func requestMicrophoneAccess() async -> Bool
}

public extension CaptureSourceCatalog {
    func hasAccess() async -> Bool { true }
    func requestAccess() async -> Bool { true }

    func restoredSource(
        from sources: [CaptureSource],
        preferredID: CaptureSourceID?
    ) -> CaptureSource? {
        if let preferredID,
           preferredID.kind == .display,
           let restored = sources.first(where: { $0.id == preferredID }) {
            return restored
        }
        let displays = sources.compactMap { source -> CaptureSource? in
            guard case .display = source else { return nil }
            return source
        }
        return displays.first {
            guard case let .display(screen) = $0 else { return false }
            return screen.isPrimary
        } ?? displays.first
    }
}

public protocol PreferencesStore: Sendable {
    func load() async -> PreferencesSnapshot
    func save(_ snapshot: PreferencesSnapshot) async
}

public enum RecordingPipelineEvent: Equatable, Sendable {
    case optionalInputLost(name: String)
    case fatal(message: String)
    case transcriptChanged(text: String, isFinal: Bool)
    case transcriptionUnavailable(message: String)
    case microphoneLevel(Double)
    case microphoneChanged(deviceID: String, name: String)
    case compilationProgress(message: String)
}

public enum RecordingPipelineControlError: Error, LocalizedError, Sendable {
    case microphoneNotActive

    public var errorDescription: String? {
        switch self {
        case .microphoneNotActive:
            "The microphone cannot be changed because microphone capture is not active."
        }
    }
}

public protocol RecordingPipeline: Sendable {
    func start(configuration: RecordingConfiguration) async throws -> AsyncStream<RecordingPipelineEvent>
    func changeSpeech(_ settings: SpeechSettings) async
    func selectMicrophoneDevice(_ deviceID: String?) async throws
    func stop() async throws -> RecordingArtifacts
    func cancel() async
}

public extension RecordingPipeline {
    func changeSpeech(_ settings: SpeechSettings) async {}
    func selectMicrophoneDevice(_ deviceID: String?) async throws {
        throw RecordingPipelineControlError.microphoneNotActive
    }
}

public protocol MediaSampleSink: Sendable {
    func appendVideo(_ sampleBuffer: CMSampleBuffer, track: UInt8) async
    func appendAudio(_ sampleBuffer: CMSampleBuffer, track: UInt8) async
}
