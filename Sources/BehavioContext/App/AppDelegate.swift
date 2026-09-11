import AppKit
import AVFoundation
import BehavioContextCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleIdentifier = "one.behavio.context"
    private let logger = Logger(
        subsystem: "one.behavio.context",
        category: "application"
    )
    let analytics: AnalyticsConsentController
    let store: RecordingSessionStore
    let shortcutRecorder = ShortcutRecorder()
    private let contextCapture: SmartContextCaptureCoordinator
    private let activeWindowResolver: ActiveWindowResolver
    private let pointerTimelineRecorder: PointerTimelineRecorder
    private let contextReturnController = RecordingContextReturnController()
    private var overlayController: WebcamOverlayPanelController?
    private var feedbackController: RecordingFeedbackPanelController?
    private var recordingResultController: RecordingResultPanelController?
    private var shortcutController: GlobalShortcutController?
    private var activeWindowResolutionTask: Task<Void, Never>?
    private weak var settingsWindow: NSWindow?
    private var settingsPresentationPending = false
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        // The launch release never initializes a telemetry SDK, even if a local
        // analytics token or a previously enabled preference is present.
        let analyticsClient = NoOpAnalyticsClient()
        let contextCapture = SmartContextCaptureCoordinator()
        self.contextCapture = contextCapture
        activeWindowResolver = ActiveWindowResolver(ownBundleIdentifier: Self.bundleIdentifier)
        pointerTimelineRecorder = PointerTimelineRecorder(coordinator: contextCapture)
        analytics = AnalyticsConsentController(client: analyticsClient)
        analytics.setEnabled(false)
        store = RecordingSessionStore(
            sourceCatalog: ScreenCaptureKitSourceCatalog(bundleIdentifier: Self.bundleIdentifier),
            recordingPipeline: ScreenCaptureRecordingPipeline(
                bundleIdentifier: Self.bundleIdentifier,
                contextCapture: contextCapture
            ),
            analyticsClient: analyticsClient
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BehavioContext launched")
        analytics.capture(.appLaunched)
        NSApp.setActivationPolicy(.regular)
        contextReturnController.startObserving()
        overlayController = WebcamOverlayPanelController(store: store) { [weak self] in
            self?.overlayController?.hide()
            self?.openSettings()
        }
        let feedbackController = RecordingFeedbackPanelController(
            store: store,
            stopRecording: { [weak self] in self?.store.stopRecording() }
        )
        let recordingResultController = RecordingResultPanelController(
            store: store,
            analytics: analytics,
            contextReturnController: contextReturnController
        )
        self.feedbackController = feedbackController
        self.recordingResultController = recordingResultController
        shortcutController = GlobalShortcutController(
            action: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.store.isInitialized else { return }
                    guard !self.shortcutRecorder.capture(self.store.globalShortcut) else { return }
                    self.toggleRecording()
                }
            },
            escapeAction: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.store.phase.isRecording else { return }
                    self.store.stopRecording()
                }
            }
        )

        store.overlayStateChanged = { [weak self] in
            guard let self else { return }
            self.overlayController?.synchronize()
            self.feedbackController?.synchronize()
            self.synchronizeRecordingInputs()
        }
        store.shortcutPreferenceChanged = { [weak self] shortcut in
            self?.shortcutController?.register(shortcut) ?? false
        }
        store.recordingWillStart = { [weak self] in
            self?.contextReturnController.captureDestination()
        }
        store.recordingResultAvailable = { [weak self] result in
            guard let self else { return }
            contextReturnController.recordingCompleted(
                result,
                retaining: Set(store.recordingResults.map(\.id))
            )
            self.recordingResultController?.present(result)
        }
        store.recordingFailureNoticeAvailable = { [weak self] in
            self?.openSettings()
        }
        store.requestScreenRecordingSettings = {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
        observeSystemEvents()

        Task {
            await store.initialize()
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BehavioContext terminating")
        shortcutRecorder.stop()
        activeWindowResolutionTask?.cancel()
        pointerTimelineRecorder.stop()
        shortcutController?.setEscapeEnabled(false)
        contextReturnController.stopObserving()
        store.cancelRecording()
        analytics.flush()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showRecordings() {
        recordingResultController?.presentSelectedRecording()
    }

    func toggleRecording() {
        if store.phase == .preparing || store.phase.isRecording {
            store.stopRecording()
            return
        }
        guard !store.phase.locksConfiguration,
              activeWindowResolutionTask == nil else { return }
        let hint: ActiveWindowHint
        do {
            hint = try ActiveWindowResolver.captureHint(
                ownBundleIdentifier: Self.bundleIdentifier
            )
        } catch {
            store.reportStartFailure(error.localizedDescription)
            return
        }
        activeWindowResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await activeWindowResolver.resolve(hint)
                guard !Task.isCancelled else { return }
                activeWindowResolutionTask = nil
                store.startRecording(with: source)
            } catch {
                activeWindowResolutionTask = nil
                store.reportStartFailure(error.localizedDescription)
            }
        }
    }

    func editWebcamLayout() {
        guard store.showsWebcamPositioningOverlay, let source = store.selectedCaptureSource else { return }
        // The Settings button is the entry point; hide that window to reveal the capture canvas.
        NSApp.keyWindow?.orderOut(nil)
        overlayController?.show()
        if case let .window(window) = source {
            CaptureWindowFocusController.focus(window) { [weak self] in
                self?.overlayController?.synchronize()
            }
        }
    }

    func openSettings() {
        overlayController?.hide()
        logger.info("Opening Settings")
        WindowPresentation.afterMenuDismissal { [weak self] in
            self?.presentSettings()
        }
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        guard settingsPresentationPending else { return }
        settingsPresentationPending = false
        WindowPresentation.afterMenuDismissal { [weak window] in
            guard let window else { return }
            WindowPresentation.bringToFront(window)
        }
    }

    private func presentSettings() {
        if let settingsWindow {
            WindowPresentation.bringToFront(settingsWindow)
            return
        }

        // SwiftUI creates the Settings window lazily. The accessor completes
        // presentation when that specific window is attached to its content.
        settingsPresentationPending = true

        if let applicationMenu = NSApp.mainMenu?.items.first?.submenu,
           let settingsItemIndex = applicationMenu.items.firstIndex(where: {
               $0.keyEquivalent == ","
                   && $0.keyEquivalentModifierMask.contains(.command)
           }) {
            applicationMenu.performActionForItem(at: settingsItemIndex)
            return
        }

        logger.warning("The SwiftUI Settings menu command was unavailable; trying the responder chain")
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            settingsPresentationPending = false
            logger.error("BehavioContext could not present its Settings scene")
        }
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.store.handleFatalSystemEvent(
                        "Recording stopped because the Mac went to sleep."
                    )
                }
            }
        )
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let deviceID = (notification.object as? AVCaptureDevice)?.uniqueID else {
                    return
                }
                Task { @MainActor in
                    guard let self else { return }
                    if deviceID == self.store.webcamDeviceID {
                        self.store.handleOptionalInputLoss("Webcam")
                    } else if deviceID == self.store.microphoneDeviceID {
                        self.store.handleOptionalInputLoss("Microphone")
                    }
                }
            }
        )
    }

    private func synchronizeRecordingInputs() {
        shortcutController?.setEscapeEnabled(store.phase.isRecording)
        if store.phase.isRecording,
           case let .window(window) = store.selectedCaptureSource {
            pointerTimelineRecorder.start(window: window)
        } else {
            pointerTimelineRecorder.stop()
        }
    }
}
