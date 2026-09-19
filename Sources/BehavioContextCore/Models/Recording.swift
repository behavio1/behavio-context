import Foundation

public struct RecordingConfiguration: Equatable, Sendable {
    public let speech: SpeechSettings
    public let source: CaptureSource
    public let capturesMicrophone: Bool
    public let microphoneDeviceID: String?
    public init(
        source: CaptureSource,
        capturesMicrophone: Bool,
        microphoneDeviceID: String?,
        speech: SpeechSettings = SpeechSettings()
    ) {
        self.speech = speech
        self.source = source
        self.capturesMicrophone = capturesMicrophone
        self.microphoneDeviceID = microphoneDeviceID
    }
}

public struct RecordingArtifacts: Equatable, Sendable {
    public let recordingURL: URL
    public let contextDirectoryURL: URL?
    public var mediaStartHostTime: Double? = nil
    public var contextFailure: String? = nil

    public init(recordingURL: URL, contextDirectoryURL: URL? = nil) {
        self.recordingURL = recordingURL
        self.contextDirectoryURL = contextDirectoryURL
    }
}

public enum RecordingPhase: Equatable, Sendable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case finalizing
    case failed(message: String)

    public var locksConfiguration: Bool {
        switch self {
        case .idle, .failed:
            false
        default:
            true
        }
    }

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    public var showsElapsedTimer: Bool {
        isRecording
    }
}

public enum RecordingEvent: Equatable, Sendable {
    case prepare
    case begin(Date)
    case stop
    case finish
    case fail(String)
    case reset
}

public enum RecordingStateMachine {
    public static func transition(from phase: RecordingPhase, event: RecordingEvent) -> RecordingPhase? {
        switch (phase, event) {
        case (.idle, .prepare), (.failed, .prepare):
            .preparing
        case (.preparing, let .begin(date)):
            .recording(startedAt: date)
        case (.preparing, .stop), (.recording, .stop):
            .finalizing
        case (.finalizing, .finish):
            .idle
        case (_, let .fail(message)):
            .failed(message: message)
        case (.failed, .reset):
            .idle
        default:
            nil
        }
    }
}
