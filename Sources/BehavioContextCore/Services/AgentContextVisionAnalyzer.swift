@preconcurrency import Vision
import CoreGraphics
import Foundation

struct PointerTextRecognition: Equatable, Sendable {
    let text: String
    let confidence: Double
}

enum AgentContextVisionAnalyzer {
    static func recognizeText(
        near pointer: PointerEvent,
        in image: CGImage
    ) throws -> PointerTextRecognition? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pl-PL", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(
                text: text,
                confidence: Double(candidate.confidence),
                bounds: observation.boundingBox
            )
        }
        guard !lines.isEmpty else { return nil }

        // Pointer coordinates originate in Quartz's top-left coordinate system.
        // Vision observations use a bottom-left origin.
        let point = CGPoint(x: pointer.normalizedX, y: 1 - pointer.normalizedY)
        guard let anchor = lines.min(by: {
            distance(from: point, to: $0.bounds) < distance(from: point, to: $1.bounds)
        }), distance(from: point, to: anchor.bounds) <= 0.065 else {
            return nil
        }

        var block = [anchor]
        var changed = true
        while changed {
            changed = false
            for line in lines where !block.contains(line) {
                guard block.contains(where: { belongsToSameTextBlock(line, $0) }) else { continue }
                block.append(line)
                changed = true
            }
        }

        let ordered = block.sorted {
            if abs($0.bounds.midY - $1.bounds.midY) > 0.012 {
                return $0.bounds.midY > $1.bounds.midY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        let text = ordered.map(\.text).joined(separator: " ")
        let confidence = ordered.map(\.confidence).reduce(0, +) / Double(ordered.count)
        return PointerTextRecognition(text: text, confidence: confidence)
    }

    private static func distance(from point: CGPoint, to rectangle: CGRect) -> CGFloat {
        let dx = max(max(rectangle.minX - point.x, 0), point.x - rectangle.maxX)
        let dy = max(max(rectangle.minY - point.y, 0), point.y - rectangle.maxY)
        return hypot(dx, dy)
    }

    private static func belongsToSameTextBlock(
        _ lhs: RecognizedLine,
        _ rhs: RecognizedLine
    ) -> Bool {
        let verticalGap = max(
            max(lhs.bounds.minY - rhs.bounds.maxY, rhs.bounds.minY - lhs.bounds.maxY),
            0
        )
        guard verticalGap <= 0.016 else { return false }

        // Wrapped text inside one control is normally aligned to either the
        // leading or trailing edge. Requiring that alignment prevents a long
        // chat bubble from transitively absorbing the sidebar and nearby UI.
        let leadingEdgesAlign = abs(lhs.bounds.minX - rhs.bounds.minX) <= 0.045
        let trailingEdgesAlign = abs(lhs.bounds.maxX - rhs.bounds.maxX) <= 0.045
        return leadingEdgesAlign || trailingEdgesAlign
    }
}

private struct RecognizedLine: Equatable {
    let text: String
    let confidence: Double
    let bounds: CGRect
}
