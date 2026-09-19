import CoreGraphics
import Foundation

public enum TranscriptStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case failed

    public static func result(hasSegments: Bool, failure: String?) -> Self {
        guard hasSegments else { return .failed }
        return failure == nil ? .complete : .partial
    }

}

public struct TranscriptWord: Codable, Equatable, Sendable {
    public let text: String
    public let startMs: Int
    public let endMs: Int

    public init(text: String, startMs: Int, endMs: Int) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }

    enum CodingKeys: String, CodingKey {
        case text
        case startMs = "start_ms"
        case endMs = "end_ms"
    }
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let startMs: Int
    public let endMs: Int
    public let text: String
    public let words: [TranscriptWord]

    public init(
        id: String,
        startMs: Int,
        endMs: Int,
        text: String,
        words: [TranscriptWord] = []
    ) {
        self.id = id
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
    }

    enum CodingKeys: String, CodingKey {
        case id, text, words
        case startMs = "start_ms"
        case endMs = "end_ms"
    }
}

public enum PointerEventKind: String, Codable, Equatable, Sendable {
    case move
    case click
    case rightClick = "right_click"
    case scroll
}

public struct PointerEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let timeMs: Int
    public let kind: PointerEventKind
    public let normalizedX: Double
    public let normalizedY: Double
    public var windowID: UInt32? = nil

    public init(
        id: String = UUID().uuidString,
        timeMs: Int,
        kind: PointerEventKind,
        normalizedX: Double,
        normalizedY: Double,
        windowID: UInt32? = nil
    ) {
        self.id = id
        self.timeMs = max(0, timeMs)
        self.kind = kind
        self.windowID = windowID
        self.normalizedX = min(1, max(0, normalizedX))
        self.normalizedY = min(1, max(0, normalizedY))
    }

    /// Preserve the beginning of a dwell without letting rapid movement erase history.
    public func shouldAppend(after last: PointerEvent?) -> Bool {
        guard let last, kind == .move, last.kind == .move, windowID == last.windowID else { return true }
        return timeMs - last.timeMs >= 80 &&
            hypot(normalizedX - last.normalizedX, normalizedY - last.normalizedY) >= 0.003
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case windowID = "window_id"
        case timeMs = "time_ms"
        case normalizedX = "normalized_x"
        case normalizedY = "normalized_y"
    }
}

public enum VisualMomentReason: String, Codable, Equatable, Sendable {
    case click
    case pointerDwell = "pointer_dwell"
    case pointingLanguage = "pointing_language"
    case visualChange = "visual_change"
    case transcriptBoundary = "transcript_boundary"
    case coverage
    case windowChange = "window_change"
}

public struct VisualMomentCandidate: Equatable, Sendable {
    public let timeMs: Int
    public let reason: VisualMomentReason
    public let score: Int
    public let pointer: PointerEvent?
    public let transcriptSegmentID: String?

    public init(
        timeMs: Int,
        reason: VisualMomentReason,
        score: Int,
        pointer: PointerEvent? = nil,
        transcriptSegmentID: String? = nil
    ) {
        self.timeMs = max(0, timeMs)
        self.reason = reason
        self.score = score
        self.pointer = pointer
        self.transcriptSegmentID = transcriptSegmentID
    }
}

public enum ContextMomentSelector {
    private static let pointingWords = [
        "tu", "tutaj", "ten", "ta", "to", "klikam", "kliknij", "pokazuję", "wskazuję", "otwieram",
    ]

    public static func select(
        durationMs: Int,
        transcript: [TranscriptSegment],
        pointerEvents: [PointerEvent],
        visualChangeTimesMs: [Int],
        maximumMoments: Int = 48
    ) -> [VisualMomentCandidate] {
        guard durationMs > 0, maximumMoments > 0 else { return [] }
        var candidates: [VisualMomentCandidate] = [
            VisualMomentCandidate(timeMs: 0, reason: .coverage, score: 25),
            VisualMomentCandidate(timeMs: max(0, durationMs - 150), reason: .coverage, score: 20),
        ]

        for segment in transcript {
            let normalized = segment.text.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "pl_PL")
            )
            let isPointing = pointingWords.contains { normalized.contains($0) }
            let segmentMiddle = segment.startMs + max(0, segment.endMs - segment.startMs) / 2
            let nearestPointer = isPointing
                ? pointerEvents.min { lhs, rhs in
                    abs(lhs.timeMs - segmentMiddle) < abs(rhs.timeMs - segmentMiddle)
                }
                : nil
            let relatedPointer = nearestPointer.flatMap {
                abs($0.timeMs - segmentMiddle) <= 1_500 ? $0 : nil
            }
            candidates.append(VisualMomentCandidate(
                timeMs: min(durationMs, max(0, relatedPointer?.timeMs ?? segment.startMs)),
                reason: isPointing ? .pointingLanguage : .transcriptBoundary,
                score: isPointing ? 90 : 48,
                pointer: relatedPointer,
                transcriptSegmentID: segment.id
            ))
            candidates.append(VisualMomentCandidate(
                timeMs: min(durationMs, max(0, segment.endMs)),
                reason: .transcriptBoundary,
                score: isPointing ? 62 : 40,
                transcriptSegmentID: segment.id
            ))
        }

        for event in pointerEvents {
            switch event.kind {
            case .click, .rightClick:
                candidates.append(VisualMomentCandidate(
                    timeMs: min(durationMs, event.timeMs + 250),
                    reason: .click,
                    score: 100,
                    pointer: event
                ))
            case .scroll:
                candidates.append(VisualMomentCandidate(
                    timeMs: min(durationMs, event.timeMs + 300),
                    reason: .visualChange,
                    score: 58,
                    pointer: event
                ))
            case .move:
                break
            }
        }

        let orderedPointers = pointerEvents.sorted { $0.timeMs < $1.timeMs }
        for (index, event) in orderedPointers.enumerated() where event.kind == .move {
            let nextTime = index + 1 < orderedPointers.count
                ? orderedPointers[index + 1].timeMs
                : durationMs
            let dwellMs = nextTime - event.timeMs
            guard dwellMs >= 700 else { continue }
            candidates.append(VisualMomentCandidate(
                timeMs: min(durationMs, event.timeMs),
                reason: .pointerDwell,
                score: min(86, 70 + dwellMs / 300),
                pointer: event
            ))
        }

        candidates.append(contentsOf: visualChangeTimesMs.map {
            VisualMomentCandidate(
                timeMs: min(durationMs, max(0, $0)),
                reason: .visualChange,
                score: 52
            )
        })

        if durationMs > 20_000 {
            for timeMs in stride(from: 10_000, to: durationMs, by: 10_000) {
                candidates.append(VisualMomentCandidate(
                    timeMs: timeMs,
                    reason: .coverage,
                    score: 18
                ))
            }
        }

        let ranked = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.timeMs < $1.timeMs
        }
        var selected: [VisualMomentCandidate] = []
        for candidate in ranked {
            guard selected.allSatisfy({ abs($0.timeMs - candidate.timeMs) >= 500 }) else { continue }
            selected.append(candidate)
            if selected.count == maximumMoments { break }
        }
        return selected.sorted { $0.timeMs < $1.timeMs }
    }

    public static func recommendedIDs(
        for moments: [ContextVisualMoment],
        maximumRecommended: Int = 8
    ) -> [String] {
        Array(
            moments.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.timeMs < $1.timeMs
            }
            .prefix(maximumRecommended)
            .map(\.id)
        )
    }
}

public struct ContextSource: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let applicationName: String
    public let windowTitle: String
    public let initialPixelWidth: Int
    public let initialPixelHeight: Int

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_id"
        case applicationName = "application_name"
        case windowTitle = "window_title"
        case initialPixelWidth = "initial_pixel_width"
        case initialPixelHeight = "initial_pixel_height"
    }
}

public struct ContextWindowInterval: Codable, Equatable, Sendable {
    public let windowID: UInt32
    public let source: ContextSource
    public let startMs: Int
    public let endMs: Int

    public init(window: WindowSource, startMs: Int, endMs: Int) {
        windowID = window.windowID
        source = ContextSource(bundleIdentifier: window.applicationBundleIdentifier,
            applicationName: window.applicationName, windowTitle: window.title,
            initialPixelWidth: window.pixelWidth, initialPixelHeight: window.pixelHeight)
        self.startMs = startMs
        self.endMs = endMs
    }
    enum CodingKeys: String, CodingKey {
        case windowID = "window_id", source
        case startMs = "start_ms", endMs = "end_ms"
    }
}

public struct ContextMicrophone: Codable, Equatable, Sendable {
    public let deviceID: String
    public let name: String

    public init(deviceID: String, name: String) {
        self.deviceID = deviceID
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case deviceID = "device_id"
    }
}

public struct ContextPointer: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public struct ContextVisualMoment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let timeMs: Int
    public let reason: VisualMomentReason
    public let score: Int
    public let path: String
    public let pointer: ContextPointer?
    public let transcriptSegmentID: String?
    public let recognizedText: String?
    public let recognitionConfidence: Double?
    public var windowID: UInt32? = nil

    enum CodingKeys: String, CodingKey {
        case id, reason, score, path, pointer
        case windowID = "window_id"
        case timeMs = "time_ms"
        case transcriptSegmentID = "transcript_segment_id"
        case recognizedText = "recognized_text"
        case recognitionConfidence = "recognition_confidence"
    }
}

public struct ContextLimits: Codable, Equatable, Sendable {
    public let recommendedCount: Int
    public let onDemandCount: Int
    public let maximumLongEdge: Int
    public let maximumCropEdge: Int

    enum CodingKeys: String, CodingKey {
        case recommendedCount = "recommended_count"
        case onDemandCount = "on_demand_count"
        case maximumLongEdge = "maximum_long_edge"
        case maximumCropEdge = "maximum_crop_edge"
    }
}

public struct AgentContextManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let recordingID: String
    public let durationMs: Int
    public let locale: String
    public let source: ContextSource
    public let microphone: ContextMicrophone?
    public let transcriptStatus: TranscriptStatus
    public let transcriptSegments: [TranscriptSegment]
    public let pointerEvents: [PointerEvent]
    public let visualMoments: [ContextVisualMoment]
    public let recommendedInputs: [String]
    public let limits: ContextLimits
    public var speechEngine: String? = nil
    public var transcriptionError: String? = nil
    public var windowTimeline: [ContextWindowInterval]? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordingID = "recording_id"
        case durationMs = "duration_ms"
        case locale, source, microphone
        case transcriptStatus = "transcript_status"
        case transcriptSegments = "transcript_segments"
        case pointerEvents = "pointer_events"
        case visualMoments = "visual_moments"
        case recommendedInputs = "recommended_inputs"
        case limits
        case speechEngine = "speech_engine"
        case transcriptionError = "transcription_error"
        case windowTimeline = "window_timeline"
    }
}

public struct AgentContextCompilation: Equatable, Sendable {
    public let directoryURL: URL
    public let manifest: AgentContextManifest

    public init(directoryURL: URL, manifest: AgentContextManifest) {
        self.directoryURL = directoryURL
        self.manifest = manifest
    }
}
