import AppKit
import CoreGraphics
import BehavioContextCore

@MainActor
final class PointerTimelineRecorder {
    private let coordinator: SmartContextCaptureCoordinator
    private var globalMonitor: Any?
    private var windowID: UInt32?
    private var startedUptime = 0.0

    init(coordinator: SmartContextCaptureCoordinator) {
        self.coordinator = coordinator
    }

    func start(window: WindowSource) {
        guard globalMonitor == nil else { return }
        windowID = window.windowID
        startedUptime = ProcessInfo.processInfo.systemUptime
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor in self?.record(event) }
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        windowID = nil
        startedUptime = 0
    }

    private func record(_ event: NSEvent) {
        guard let windowID,
              let bounds = Self.quartzBounds(windowID: windowID),
              let point = event.cgEvent?.location,
              bounds.contains(point) else { return }
        let kind: PointerEventKind
        switch event.type {
        case .leftMouseDown: kind = .click
        case .rightMouseDown: kind = .rightClick
        case .scrollWheel: kind = .scroll
        default: kind = .move
        }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        let pointerEvent = PointerEvent(
            timeMs: Int(elapsed * 1_000),
            kind: kind,
            normalizedX: (point.x - bounds.minX) / bounds.width,
            normalizedY: (point.y - bounds.minY) / bounds.height
        )
        Task { await coordinator.recordPointerEvent(pointerEvent) }
    }

    private static func quartzBounds(windowID: UInt32) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowID)
        ) as? [[String: Any]],
        let window = windows.first,
        let dictionary = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
