import Foundation

public struct RecordingConfiguration: Equatable, Sendable {
    public let speech: SpeechSettings
    public let source: CaptureSource
    public let capturesSystemAudio: Bool
    public let capturesMicrophone: Bool
    public let microphoneDeviceID: String?
    public let capturesWebcam: Bool
    public let webcamDeviceID: String?
    public let blursWebcamBackground: Bool
    public let webcamLayout: WebcamLayout
    public init(
        source: CaptureSource,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool,
        microphoneDeviceID: String?,
        capturesWebcam: Bool,
        webcamDeviceID: String?,
        webcamLayout: WebcamLayout,
        blursWebcamBackground: Bool = false,
        speech: SpeechSettings = SpeechSettings()
    ) {
        self.speech = speech
        self.source = source
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.capturesWebcam = capturesWebcam
        self.webcamDeviceID = webcamDeviceID
        self.webcamLayout = webcamLayout
        self.blursWebcamBackground = blursWebcamBackground
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
