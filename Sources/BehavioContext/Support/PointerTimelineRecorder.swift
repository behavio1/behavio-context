import AppKit
import CoreGraphics
import BehavioContextCore

@MainActor
final class PointerTimelineRecorder {
    private let coordinator: SmartContextCaptureCoordinator
    private var globalMonitor: Any?
    private var samplingTask: Task<Void, Never>?
    private var windowID: UInt32?
    private var startedUptime = 0.0
    private var canvasAspect = 1.0

    init(coordinator: SmartContextCaptureCoordinator) {
        self.coordinator = coordinator
    }

    func start(window: WindowSource) {
        guard globalMonitor == nil else { return }
        windowID = window.windowID
        canvasAspect = Double(window.pixelWidth) / Double(window.pixelHeight)
        startedUptime = ProcessInfo.processInfo.systemUptime
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.recordPosition()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor in self?.record(event) }
        }
    }

    func follow(window: WindowSource?) { windowID = window?.windowID }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        windowID = nil
        startedUptime = 0
    }

    private func record(_ event: NSEvent) {
        let kind: PointerEventKind
        switch event.type {
        case .leftMouseDown: kind = .click
        case .rightMouseDown: kind = .rightClick
        case .scrollWheel: kind = .scroll
        default: kind = .move
        }
        recordPosition(kind: kind, point: event.cgEvent?.location)
    }

    private func recordPosition(kind: PointerEventKind = .move, point: CGPoint? = nil) {
        guard let windowID,
              (try? ActiveWindowResolver.captureHint(ownBundleIdentifier: "one.behavio.context").windowID) == windowID,
              let bounds = Self.quartzBounds(windowID: windowID),
              let point = point ?? CGEvent(source: nil)?.location,
              bounds.contains(point) else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime
        let aspect = bounds.width / bounds.height
        let width = min(1, aspect / canvasAspect)
        let height = min(1, canvasAspect / aspect)
        let pointerEvent = PointerEvent(
            timeMs: Int(elapsed * 1_000),
            kind: kind,
            normalizedX: (1 - width) / 2 + width * (point.x - bounds.minX) / bounds.width,
            normalizedY: (1 - height) / 2 + height * (point.y - bounds.minY) / bounds.height,
            windowID: windowID
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
