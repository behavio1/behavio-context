import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class RecordingSessionStore {
    public private(set) var phase: RecordingPhase = .idle {
        didSet {
            overlayStateChanged?()
            logger.info("Recording phase changed to \(self.phase.logName, privacy: .public)")
        }
    }
    public private(set) var captureSources: [CaptureSource] = []
    public private(set) var microphones: [CaptureDeviceOption] = []
    public private(set) var warningMessage: String? {
        didSet {
            guard warningMessage != oldValue else { return }
            overlayStateChanged?()
        }
    }
    public private(set) var completionNotice: String? {
        didSet { overlayStateChanged?() }
    }
    public func showCompletionNotice(_ message: String) {
        completionNotice = AppLocalization.text(message, locale: effectiveLocale)
    }

    public private(set) var recordingFailureNotice: RecordingFailureNotice?
    public private(set) var elapsedSeconds: TimeInterval = 0 {
        didSet { overlayStateChanged?() }
    }
    public private(set) var liveTranscript = "" {
        didSet { overlayStateChanged?() }
    }
    public private(set) var liveTranscriptIsFinal = false {
        didSet { overlayStateChanged?() }
    }
    public private(set) var microphoneLevel = 0.0 {
        didSet { overlayStateChanged?() }
    }
    public private(set) var compilationMessage: String? {
        didSet { overlayStateChanged?() }
    }
    public private(set) var isInitialized = false
    public private(set) var screenCaptureAccessDenied = false
    public private(set) var latestRecordingResult: RecordingResult?
    public private(set) var recordingResults: [RecordingResult] = []
    public private(set) var selectedRecordingID: RecordingResult.ID?

    public var lastLocalRecordingURL: URL? { latestRecordingResult?.fileURL }
    public var selectedRecordingResult: RecordingResult? {
        guard let selectedRecordingID else { return latestRecordingResult }
        return recordingResults.first { $0.id == selectedRecordingID }
            ?? latestRecordingResult
    }

    public private(set) var selectedCaptureSourceID: CaptureSourceID? {
        didSet {
            if selectedCaptureSourceID != nil {
                requiresCaptureSourceSelection = false
            }
            persist()
            overlayStateChanged?()
        }
    }
    public var capturesMicrophone: Bool { didSet { persist() } }
    public var microphoneDeviceID: String? {
        didSet {
            persist()
            overlayStateChanged?()
        }
    }
    public let speechModelInstaller = SpeechModelInstaller()
    public var speech: SpeechSettings {
        didSet {
            persist()
            speechReadiness = SpeechReadiness.check(speech)
            overlayStateChanged?()
        }
    }
    public private(set) var speechReadiness: SpeechReadiness = .permissionRequired
    public func selectSpeechLanguage(_ language: SpeechLanguage) async {
        speech.language = language
        if phase.isRecording { await recordingPipeline.changeSpeech(speech) }
    }
    public func refreshSpeechReadiness() { speechReadiness = SpeechReadiness.check(speech) }

    public var language: AppLanguage {
        didSet {
            persist()
        }
    }
    public private(set) var globalShortcut: GlobalShortcut
    public private(set) var shortcutRegistrationFailed = false
    @ObservationIgnored private let sourceCatalog: any CaptureSourceCatalog
    @ObservationIgnored private let captureAuthorization: any CaptureAuthorization
    @ObservationIgnored private let preferencesStore: any PreferencesStore
    @ObservationIgnored private let recordingHistoryStore: any RecordingHistoryStore
    @ObservationIgnored private let recordingPipeline: any RecordingPipeline
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var historyPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var pipelineIsRecording = false
    @ObservationIgnored private var isLoadingPreferences = true
    @ObservationIgnored private var requiresCaptureSourceSelection = false
    @ObservationIgnored private let logger = Logger(
        subsystem: "one.behavio.context",
        category: "recording-session"
    )

    /// Called synchronously for accepted starts, before preparation changes app focus.
    @ObservationIgnored public var recordingWillStart: (() -> Void)?
    @ObservationIgnored public var recordingResultAvailable: ((RecordingResult) -> Void)?
    @ObservationIgnored public var recordingFailureNoticeAvailable: (() -> Void)?
    @ObservationIgnored public var shortcutPreferenceChanged: ((GlobalShortcut) -> Bool)?
    @ObservationIgnored public var overlayStateChanged: (() -> Void)?
    @ObservationIgnored public var requestScreenRecordingSettings: (() -> Void)?

    public convenience init(
        sourceCatalog: any CaptureSourceCatalog = ScreenCaptureKitSourceCatalog(),
        captureAuthorization: any CaptureAuthorization = SystemCaptureAuthorization(),
        preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore(),
        historyStore: any RecordingHistoryStore = FileRecordingHistoryStore(),
        recordingPipeline: any RecordingPipeline = ScreenCaptureRecordingPipeline()
    ) {
        self.init(
            sourceCatalog: sourceCatalog,
            captureAuthorization: captureAuthorization,
            preferencesStore: preferencesStore,
            recordingHistoryStore: historyStore,
            recordingPipeline: recordingPipeline
        )
    }

    init(
        sourceCatalog: any CaptureSourceCatalog,
        captureAuthorization: any CaptureAuthorization,
        preferencesStore: any PreferencesStore,
        recordingHistoryStore: any RecordingHistoryStore = VolatileRecordingHistoryStore(),
        recordingPipeline: any RecordingPipeline
    ) {
        self.sourceCatalog = sourceCatalog
        self.captureAuthorization = captureAuthorization
        self.preferencesStore = preferencesStore
        self.recordingHistoryStore = recordingHistoryStore
        self.recordingPipeline = recordingPipeline
        let defaults = PreferencesSnapshot.defaults
        selectedCaptureSourceID = defaults.selectedCaptureSourceID
        capturesMicrophone = defaults.capturesMicrophone
        microphoneDeviceID = defaults.microphoneDeviceID
        speech = defaults.speech
        language = defaults.language
        globalShortcut = defaults.globalShortcut
    }

    public var screens: [ScreenSource] {
        captureSources.compactMap {
            if case let .display(screen) = $0 { return screen }
            return nil
        }
    }

    public var windows: [WindowSource] {
        captureSources.compactMap {
            if case let .window(window) = $0 { return window }
            return nil
        }
    }

    public var selectedCaptureSource: CaptureSource? {
        guard let selectedCaptureSourceID else { return nil }
        return captureSources.first(where: { $0.id == selectedCaptureSourceID })
    }

    public var selectedScreen: ScreenSource? {
        guard case let .display(screen) = selectedCaptureSource else { return nil }
        return screen
    }

    public var selectedMicrophoneName: String {
        guard capturesMicrophone else { return AppLocalization.text("Microphone off", locale: effectiveLocale) }
        if let selected = microphones.first(where: { $0.id == microphoneDeviceID }) {
            return selected.name
        }
        return CaptureDeviceCatalog.microphone(withID: microphoneDeviceID)?.localizedName
            ?? AppLocalization.text("Default microphone", locale: effectiveLocale)
    }

    public var configurationIsLocked: Bool { phase.locksConfiguration }

    public var recordingActionIsUnavailable: Bool {
        phase == .finalizing
            || (!phase.isRecording && phase != .preparing && selectedCaptureSource == nil)
    }

    public var hudMessage: String? {
        if let warningMessage { return AppLocalization.text(warningMessage, locale: effectiveLocale) }
        if case let .failed(message) = phase { return AppLocalization.text(message, locale: effectiveLocale) }
        return nil
    }

    public var activeWindowName: String?

    public var effectiveLocale: Locale {
        Locale(identifier: language.resolvedIdentifier())
    }

    public var usesRightToLeftLayout: Bool {
        false
    }

    public func initialize() async {
        let snapshot = await preferencesStore.load()
        apply(snapshot)
        await restoreRecordingHistory()

        // The global stop/start affordances must become available even when a
        // first-run TCC request is still pending. Capture discovery can block
        // while macOS presents or refreshes its privacy UI.
        isLoadingPreferences = false
        isInitialized = true
        persist()
        if !updateGlobalShortcut(globalShortcut), globalShortcut != .defaultShortcut {
            updateGlobalShortcut(.defaultShortcut)
        }

        screenCaptureAccessDenied = !(await sourceCatalog.hasAccess())
        if screenCaptureAccessDenied {
            captureSources = []
            selectedCaptureSourceID = nil
            refreshCaptureDevices()
        } else {
            await refreshSources()
        }
        await prepareEnabledCapturePermissions()
    }

    @discardableResult
    public func updateGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        guard shortcutPreferenceChanged?(shortcut) ?? true else {
            shortcutRegistrationFailed = true
            return false
        }
        shortcutRegistrationFailed = false
        globalShortcut = shortcut
        persist()
        return true
    }

    public func selectRecording(_ id: RecordingResult.ID) {
        guard selectedRecordingID != id,
              recordingResults.contains(where: { $0.id == id }) else { return }
        selectedRecordingID = id
        scheduleRecordingHistoryPersistence()
    }

    @discardableResult
    public func deleteSelectedRecording() async -> Bool {
        guard let deletionTarget = selectedRecordingResult else {
            return false
        }
        let deletionTargetID = deletionTarget.id

        await historyPersistenceTask?.value
        guard let index = recordingResults.firstIndex(where: { $0.id == deletionTargetID }) else {
            return false
        }
        let result = recordingResults[index]

        do {
            try await recordingHistoryStore.delete(recordingHistoryEntry(for: result))
        } catch {
            warningMessage = error.localizedDescription
            logger.error("Could not delete recording: \(error.localizedDescription, privacy: .public)")
            return false
        }

        recordingResults.remove(at: index)
        latestRecordingResult = recordingResults.last
        if recordingResults.isEmpty {
            selectedRecordingID = nil
        } else if index < recordingResults.count {
            selectedRecordingID = recordingResults[index].id
        } else {
            selectedRecordingID = recordingResults.last?.id
        }
        await persistRecordingHistory()
        return true
    }

    public func refreshSources() async {
        guard await sourceCatalog.hasAccess() else {
            screenCaptureAccessDenied = true
            captureSources = []
            selectedCaptureSourceID = nil
            refreshCaptureDevices()
            return
        }

        do {
            let previousSelection = selectedCaptureSource
            let available = try await sourceCatalog.sources()
            screenCaptureAccessDenied = false
            captureSources = available
            let restored: CaptureSource?
            if case let .window(previousWindow) = previousSelection {
                restored = available.first {
                    guard case let .window(candidate) = $0 else { return false }
                    return candidate.matchesRuntimeIdentity(of: previousWindow)
                }
                if restored == nil {
                    requiresCaptureSourceSelection = true
                }
            } else if requiresCaptureSourceSelection {
                restored = nil
            } else {
                restored = sourceCatalog.restoredSource(
                    from: available,
                    preferredID: selectedCaptureSourceID
                )
            }
            selectedCaptureSourceID = restored?.id
        } catch {
            logger.error("Could not refresh capture sources: \(String(reflecting: error), privacy: .public)")
            if error.localizedDescription.localizedCaseInsensitiveContains("TCC") {
                screenCaptureAccessDenied = true
                warningMessage = "Screen Recording access is unavailable for this build. Refresh it once in Privacy & Security."
            } else {
                warningMessage = error.localizedDescription
            }
            if selectedCaptureSourceID?.kind == .window {
                requiresCaptureSourceSelection = true
            }
            captureSources = []
            selectedCaptureSourceID = nil
        }
        refreshCaptureDevices()
    }

    private func refreshCaptureDevices() {
        microphones = CaptureDeviceCatalog.microphones()
        if microphoneDeviceID == nil || !microphones.contains(where: { $0.id == microphoneDeviceID }) {
            microphoneDeviceID = microphones.first?.id
        }
    }

    public func requestScreenCaptureAccess() {
        Task {
            let granted = await sourceCatalog.requestAccess()
            screenCaptureAccessDenied = !granted
            if granted {
                warningMessage = nil
                await refreshSources()
            } else {
                warningMessage = "Allow Screen Recording for UI Screen Context, then reopen or refresh sources."
                requestScreenRecordingSettings?()
            }
        }
    }

    public func selectCaptureSource(_ sourceID: CaptureSourceID) {
        guard !configurationIsLocked,
              captureSources.contains(where: { $0.id == sourceID }) else {
            return
        }
        selectedCaptureSourceID = sourceID
    }

    public func setMicrophoneEnabled(_ enabled: Bool) async {
        guard !configurationIsLocked else { return }
        guard enabled else {
            capturesMicrophone = false
            return
        }
        guard await captureAuthorization.requestMicrophoneAccess() else {
            capturesMicrophone = false
            warningMessage = "Microphone permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        capturesMicrophone = true
        warningMessage = nil
    }

    public func selectMicrophoneDevice(_ deviceID: String?) async {
        guard phase != .preparing, phase != .finalizing else { return }
        if capturesMicrophone,
           !phase.isRecording,
           !(await captureAuthorization.requestMicrophoneAccess()) {
            capturesMicrophone = false
            warningMessage = "Microphone permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        if phase.isRecording {
            let previousID = microphoneDeviceID
            do {
                try await recordingPipeline.selectMicrophoneDevice(deviceID)
                microphoneDeviceID = deviceID
                warningMessage = nil
            } catch {
                microphoneDeviceID = previousID
                warningMessage = AppLocalization.text("Couldn’t switch microphone.", locale: effectiveLocale) + " " + error.localizedDescription
            }
        } else {
            microphoneDeviceID = deviceID
        }
    }

    public func startRecording() {
        guard !phase.locksConfiguration, startTask == nil, stopTask == nil else { return }
        warningMessage = nil
        guard let source = selectedCaptureSource else {
            fail("No screen or window is available. Check Screen Recording permission and refresh sources.")
            return
        }

        recordingWillStart?()
        let sessionID = UUID()
        activeSessionID = sessionID
        elapsedSeconds = 0
        completionNotice = nil
        liveTranscript = ""
        liveTranscriptIsFinal = false
        microphoneLevel = 0
        compilationMessage = nil
        phase = .preparing
        logger.info("Recording start requested")
        startTask = Task { [weak self] in
            await self?.runStart(
                source: source,
                sessionID: sessionID
            )
        }
    }

    public func startRecording(with source: CaptureSource) {
        guard !phase.locksConfiguration, startTask == nil, stopTask == nil else { return }
        if !captureSources.contains(where: { $0.id == source.id }) {
            captureSources.append(source)
        }
        selectedCaptureSourceID = source.id
        startRecording()
    }

    public func reportStartFailure(_ message: String) {
        guard !phase.locksConfiguration else { return }
        warningMessage = AppLocalization.text(message, locale: effectiveLocale)
        fail(message)
    }

    public func stopRecording() {
        guard stopTask == nil else { return }
        guard phase == .preparing || phase.isRecording else { return }

        logger.info("Recording stop requested")
        let pendingStartTask = startTask
        let wasPreparing = phase == .preparing
        if wasPreparing {
            activeSessionID = nil
        }
        phase = .finalizing
        pendingStartTask?.cancel()
        startTask = nil
        timerTask?.cancel()
        timerTask = nil
        microphoneLevel = 0

        stopTask = Task { [weak self] in
            guard let self else { return }
            if wasPreparing {
                await recordingPipeline.cancel()
            }
            await pendingStartTask?.value
            guard pipelineIsRecording else {
                activeSessionID = nil
                stopTask = nil
                phase = .idle
                elapsedSeconds = 0
                return
            }
            await finishRecording()
        }
    }

    public func toggleRecording() {
        if phase == .preparing || phase.isRecording {
            stopRecording()
        } else if !phase.locksConfiguration {
            startRecording()
        }
    }

    public func cancelRecording() {
        activeSessionID = nil
        startTask?.cancel()
        startTask = nil
        stopTask?.cancel()
        stopTask = nil
        eventTask?.cancel()
        eventTask = nil
        timerTask?.cancel()
        timerTask = nil
        pipelineIsRecording = false
        Task { await recordingPipeline.cancel() }
        phase = .idle
        elapsedSeconds = 0
    }

    public func clearWarning() {
        warningMessage = nil
    }

    public func dismissFeedback() {
        completionNotice = nil
        warningMessage = nil
        if case .failed = phase {
            phase = .idle
        }
    }

    public func dismissRecordingFailureNotice() {
        recordingFailureNotice = nil
    }

    public func handleFatalSystemEvent(_ message: String) {
        guard phase == .preparing || phase.isRecording else { return }
        logger.error("Recording failed: \(message, privacy: .public)")
        warningMessage = AppLocalization.text(message, locale: effectiveLocale)
        stopRecording()
    }

    public func handleOptionalInputLoss(_ name: String) {
        guard phase.locksConfiguration else { return }
        warningMessage = "\(name) disconnected. The recording is continuing without it."
    }

    private func runStart(
        source: CaptureSource,
        sessionID: UUID
    ) async {
        do {
            try Task.checkCancellation()
            let configuration = RecordingConfiguration(
                source: source,
                capturesMicrophone: capturesMicrophone,
                microphoneDeviceID: microphoneDeviceID,
                speech: speech
            )
            let events = try await recordingPipeline.start(configuration: configuration)
            pipelineIsRecording = true
            try Task.checkCancellation()
            guard activeSessionID == sessionID else { throw CancellationError() }

            startTask = nil
            let startedAt = Date()
            phase = .recording(startedAt: startedAt)
            startElapsedTimer(sessionID: sessionID, startedAt: startedAt)
            eventTask = Task { [weak self] in
                for await event in events {
                    guard let self,
                          !Task.isCancelled,
                          activeSessionID == sessionID else { return }
                    handle(event)
                }
            }
        } catch is CancellationError {
            pipelineIsRecording = false
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            await recordingPipeline.cancel()
            startTask = nil
            phase = .idle
        } catch {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            startTask = nil
            pipelineIsRecording = false
            await recordingPipeline.cancel()
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let artifacts: RecordingArtifacts
        do {
            artifacts = try await recordingPipeline.stop()
            await eventTask?.value
            eventTask = nil
        } catch is CancellationError {
            activeSessionID = nil
            pipelineIsRecording = false
            eventTask?.cancel()
            eventTask = nil
            stopTask = nil
            phase = .idle
            return
        } catch {
            activeSessionID = nil
            pipelineIsRecording = false
            eventTask?.cancel()
            eventTask = nil
            stopTask = nil
            let recoveryError = error as? RecordingRecoveryError
            let diagnosticDescription = recoveryError?.diagnosticDescription
                ?? String(reflecting: error)
            logger.error(
                "Recording finalization failed: \(diagnosticDescription, privacy: .public)"
            )
            recordingFailureNotice = RecordingFailureNotice(
                kind: recoveryError == nil
                    ? .recordingNotSaved
                    : .partialRecordingPreserved,
                recoveryURL: recoveryError?.recoveryURL
            )
            warningMessage = error.localizedDescription
            phase = .failed(message: error.localizedDescription)
            recordingFailureNoticeAvailable?()
            return
        }

        activeSessionID = nil
        pipelineIsRecording = false
        let result = RecordingResult(
            fileURL: artifacts.recordingURL,
            contextDirectoryURL: artifacts.contextDirectoryURL
        )
        latestRecordingResult = result
        recordingResults.removeAll { $0.id == result.id }
        recordingResults.append(result)
        selectedRecordingID = result.id
        await persistRecordingHistory()
        elapsedSeconds = 0
        microphoneLevel = 0
        compilationMessage = nil
        phase = .idle
        stopTask = nil
        recordingResultAvailable?(result)
        if let contextFailure = artifacts.contextFailure {
            warningMessage = contextFailure
            recordingFailureNotice = RecordingFailureNotice(kind: .contextUnavailable, recoveryURL: artifacts.recordingURL)
            recordingFailureNoticeAvailable?()
        }
        logger.info("Local recording finalized")
    }

    public func reloadRecordingHistory() async {
        guard !configurationIsLocked else { return }
        await historyPersistenceTask?.value
        await restoreRecordingHistory()
    }

    private func restoreRecordingHistory() async {
        do {
            let history = try await recordingHistoryStore.load()
            recordingResults = history.recordings.map { entry in
                RecordingResult(
                    id: entry.id,
                    fileURL: entry.fileURL,
                    recordedAt: entry.recordedAt
                )
            }
            latestRecordingResult = recordingResults.last
            let validIDs = Set(recordingResults.map(\.id))
            if let persistedID = history.selectedRecordingID,
               validIDs.contains(persistedID) {
                selectedRecordingID = persistedID
            } else {
                selectedRecordingID = latestRecordingResult?.id
            }
        } catch {
            logger.error("Could not load recording history: \(error.localizedDescription, privacy: .public)")
            recordingResults = []
            latestRecordingResult = nil
            selectedRecordingID = nil
        }
    }

    private func scheduleRecordingHistoryPersistence() {
        let previousTask = historyPersistenceTask
        let snapshot = recordingHistorySnapshot
        historyPersistenceTask = Task { [recordingHistoryStore, logger] in
            await previousTask?.value
            do {
                try await recordingHistoryStore.save(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Could not save recording history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistRecordingHistory() async {
        await historyPersistenceTask?.value
        historyPersistenceTask = nil
        do {
            try await recordingHistoryStore.save(recordingHistorySnapshot)
        } catch {
            logger.error("Could not save recording history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var recordingHistorySnapshot: RecordingHistorySnapshot {
        RecordingHistorySnapshot(
            recordings: recordingResults.map { recordingHistoryEntry(for: $0) },
            selectedRecordingID: selectedRecordingID
        )
    }

    private func recordingHistoryEntry(for result: RecordingResult) -> RecordingHistoryEntry {
        RecordingHistoryEntry(
            id: result.id,
            fileURL: result.fileURL,
            recordedAt: result.recordedAt
        )
    }

    private func prepareEnabledCapturePermissions() async {
        if capturesMicrophone { await setMicrophoneEnabled(true) }
    }

    private func handle(_ event: RecordingPipelineEvent) {
        switch event {
        case let .optionalInputLost(name):
            warningMessage = "\(name) disconnected. The recording is continuing without it."
        case let .fatal(message):
            handleFatalSystemEvent(message)
        case let .transcriptChanged(text, isFinal):
            liveTranscript = text
            liveTranscriptIsFinal = isFinal
        case let .transcriptionUnavailable(message):
            liveTranscript = message
            liveTranscriptIsFinal = true
        case let .microphoneLevel(level):
            microphoneLevel = min(1, max(0, level))
        case let .microphoneChanged(deviceID, name):
            microphoneDeviceID = deviceID
            logger.info("Active microphone is \(name, privacy: .public)")
        case let .compilationProgress(message):
            compilationMessage = AppLocalization.text(message, locale: effectiveLocale)
        }
    }

    private func startElapsedTimer(sessionID: UUID, startedAt: Date) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, activeSessionID == sessionID else { return }
                elapsedSeconds = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fail(_ message: String) {
        activeSessionID = nil
        elapsedSeconds = 0
        phase = .failed(message: message)
    }

    private func apply(_ snapshot: PreferencesSnapshot) {
        let lastSourceKind = snapshot.lastCaptureSourceKind
            ?? snapshot.selectedCaptureSourceID?.kind
        requiresCaptureSourceSelection = lastSourceKind == .window
        selectedCaptureSourceID = requiresCaptureSourceSelection
            ? nil
            : snapshot.selectedCaptureSourceID
        capturesMicrophone = snapshot.capturesMicrophone
        microphoneDeviceID = snapshot.microphoneDeviceID
        speech = snapshot.speech
        language = snapshot.language
        globalShortcut = snapshot.globalShortcut
    }

    private func persist() {
        guard !isLoadingPreferences else { return }
        let snapshot = PreferencesSnapshot(
            selectedCaptureSourceID: selectedCaptureSourceID?.kind == .display
                ? selectedCaptureSourceID
                : nil,
            lastCaptureSourceKind: selectedCaptureSourceID?.kind
                ?? (requiresCaptureSourceSelection ? .window : nil),
            capturesMicrophone: capturesMicrophone,
            microphoneDeviceID: microphoneDeviceID,
            language: language,
            speech: speech,
            globalShortcut: globalShortcut
        )
        persistenceTask?.cancel()
        persistenceTask = Task { [preferencesStore] in
            guard !Task.isCancelled else { return }
            await preferencesStore.save(snapshot.sanitizedForPersistence)
        }
    }
}

private extension RecordingPhase {
    var logName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .finalizing: "finalizing"
        case .failed: "failed"
        }
    }
}
