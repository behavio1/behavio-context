import Foundation
import XCTest
@testable import BehavioContextCore

final class AgentContextTests: XCTestCase {
    func testPointingLanguageAndClickWinSelectionWithoutExceedingLimits() {
        let transcript = TranscriptSegment(
            id: "segment-001",
            startMs: 1_000,
            endMs: 2_000,
            text: "Tutaj klikam ten przycisk"
        )
        let click = PointerEvent(
            timeMs: 1_400,
            kind: .click,
            normalizedX: 0.5,
            normalizedY: 0.5
        )
        let selected = ContextMomentSelector.select(
            durationMs: 120_000,
            transcript: [transcript],
            pointerEvents: [click],
            visualChangeTimesMs: Array(stride(from: 0, through: 120_000, by: 600)),
            maximumMoments: 48
        )

        XCTAssertLessThanOrEqual(selected.count, 48)
        XCTAssertTrue(selected.contains { $0.reason == .click })
        XCTAssertTrue(selected.contains { $0.pointer != nil && abs($0.timeMs - 1_400) <= 500 })
    }

    func testPointerDwellCreatesAHighValueMoment() {
        let pointerEvents = [
            PointerEvent(timeMs: 1_000, kind: .move, normalizedX: 0.4, normalizedY: 0.4),
            PointerEvent(timeMs: 2_200, kind: .move, normalizedX: 0.7, normalizedY: 0.7),
        ]

        let selected = ContextMomentSelector.select(
            durationMs: 3_000,
            transcript: [],
            pointerEvents: pointerEvents,
            visualChangeTimesMs: []
        )

        XCTAssertTrue(selected.contains { $0.reason == .pointerDwell && $0.timeMs == 1_000 })
    }

    func testPointerCoordinatesAndTimeAreClamped() {
        let event = PointerEvent(
            timeMs: -1,
            kind: .move,
            normalizedX: -4,
            normalizedY: 2
        )
        XCTAssertEqual(event.timeMs, 0)
        XCTAssertEqual(event.normalizedX, 0)
        XCTAssertEqual(event.normalizedY, 1)
    }
}
