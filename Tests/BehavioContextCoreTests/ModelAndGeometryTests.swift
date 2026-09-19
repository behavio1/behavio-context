import CoreGraphics
import XCTest
@testable import BehavioContextCore

final class ModelAndGeometryTests: XCTestCase {
    func testSourceRestorationUsesOnlyPersistentDisplayIDs() async throws {
        let primary = makeScreen(id: 1, isPrimary: true)
        let secondary = makeScreen(id: 2, origin: CGPoint(x: -1920, y: 0))
        let window = makeWindow(id: 12)
        let sources: [CaptureSource] = [.display(primary), .display(secondary), .window(window)]
        let catalog = StaticSourceCatalog(values: sources)

        let restoredDisplay = catalog.restoredSource(from: sources, preferredID: .display(2))
        XCTAssertEqual(restoredDisplay?.id, .display(2))
        let rejectedWindow = catalog.restoredSource(from: sources, preferredID: .window(12))
        XCTAssertEqual(rejectedWindow?.id, .display(1))
        XCTAssertNil(catalog.restoredSource(
            from: [.window(window)],
            preferredID: .window(12)
        ))
    }

    func testOutputProfilePreservesAspectCapsAt4KAndUsesEvenDimensions() {
        let fiveK = makeScreen(id: 1, width: 5120, height: 2880)
        let profile = OutputProfile.make(for: fiveK)
        XCTAssertEqual(profile.width, 3840)
        XCTAssertEqual(profile.height, 2160)
        XCTAssertEqual(profile.videoBitRate, 6_000_000)
        XCTAssertEqual(profile.width % 2, 0)
        XCTAssertEqual(profile.height % 2, 0)

        let belowFullHD = OutputProfile.make(
            for: makeScreen(id: 2, width: 1440, height: 900)
        )
        XCTAssertEqual(belowFullHD.videoBitRate, 4_500_000)
    }

    func testWindowOutputProfileUsesWindowPixelDimensions() {
        let window = makeWindow(id: 9, width: 2561, height: 1441)
        let profile = OutputProfile.make(for: .window(window))

        XCTAssertEqual(profile.width, 2560)
        XCTAssertEqual(profile.height, 1440)
        XCTAssertEqual(profile.videoBitRate, 6_000_000)
    }

    func testLiveFilterGeometryDeterminesWindowOutputProfile() {
        let dimensions = ScreenCaptureKitContentFilterFactory.pixelDimensions(
            contentRect: CGRect(x: 40, y: 80, width: 1400, height: 900),
            pointPixelScale: 2
        )
        let profile = OutputProfile.make(
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )

        XCTAssertEqual(dimensions.width, 2800)
        XCTAssertEqual(dimensions.height, 1800)
        XCTAssertEqual(profile.width, 2800)
        XCTAssertEqual(profile.height, 1800)
    }

    func testRuntimeWindowIdentityRejectsReusedWindowID() {
        let selected = makeWindow(id: 12, title: "Roadmap", applicationName: "Notes")
        let reusedID = makeWindow(id: 12, title: "Inbox", applicationName: "Notes")

        XCTAssertFalse(reusedID.matchesRuntimeIdentity(of: selected))
        XCTAssertTrue(selected.matchesRuntimeIdentity(of: selected))
    }

    func testScreenCaptureWindowFrameConvertsToAppKitCoordinates() {
        let converted = ScreenCaptureKitSourceCatalog.appKitFrame(
            fromScreenCaptureFrame: CGRect(x: -1200, y: 920, width: 800, height: 500),
            primaryDisplayMaxY: 1080
        )

        XCTAssertEqual(converted, CGRect(x: -1200, y: -340, width: 800, height: 500))
    }

    func testEveryValidRecordingStateTransition() {
        let now = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(RecordingStateMachine.transition(from: .idle, event: .prepare), .preparing)
        XCTAssertEqual(RecordingStateMachine.transition(from: .preparing, event: .begin(now)), .recording(startedAt: now))
        XCTAssertEqual(RecordingStateMachine.transition(from: .recording(startedAt: now), event: .stop), .finalizing)
        XCTAssertEqual(RecordingStateMachine.transition(from: .finalizing, event: .finish), .idle)
        XCTAssertEqual(RecordingStateMachine.transition(from: .idle, event: .fail("error")), .failed(message: "error"))
        XCTAssertEqual(RecordingStateMachine.transition(from: .failed(message: "error"), event: .reset), .idle)
        XCTAssertNil(RecordingStateMachine.transition(from: .idle, event: .begin(now)))
    }

    func testElapsedTimerIsVisibleOnlyWhileRecording() {
        XCTAssertFalse(RecordingPhase.preparing.showsElapsedTimer)
        XCTAssertTrue(RecordingPhase.recording(startedAt: Date()).showsElapsedTimer)
        XCTAssertFalse(RecordingPhase.finalizing.showsElapsedTimer)
    }
}

private actor StaticSourceCatalog: CaptureSourceCatalog {
    let values: [CaptureSource]
    init(values: [CaptureSource]) { self.values = values }
    func sources() -> [CaptureSource] { values }
}

func makeScreen(
    id: UInt32,
    width: Int = 1920,
    height: Int = 1080,
    origin: CGPoint = .zero,
    scale: Double = 1,
    isPrimary: Bool = false
) -> ScreenSource {
    ScreenSource(
        displayID: id,
        name: "Display \(id)",
        pixelWidth: width,
        pixelHeight: height,
        frame: CGRect(
            origin: origin,
            size: CGSize(width: Double(width) / scale, height: Double(height) / scale)
        ),
        backingScaleFactor: scale,
        isPrimary: isPrimary
    )
}

func makeWindow(
    id: UInt32,
    title: String = "Document",
    applicationName: String = "Example",
    width: Int = 1280,
    height: Int = 720,
    origin: CGPoint = CGPoint(x: 120, y: 80),
    scale: Double = 2
) -> WindowSource {
    WindowSource(
        windowID: id,
        title: title,
        applicationName: applicationName,
        applicationBundleIdentifier: "com.example.app",
        processIdentifier: 123,
        pixelWidth: width,
        pixelHeight: height,
        frame: CGRect(
            origin: origin,
            size: CGSize(width: Double(width) / scale, height: Double(height) / scale)
        ),
        backingScaleFactor: scale
    )
}
