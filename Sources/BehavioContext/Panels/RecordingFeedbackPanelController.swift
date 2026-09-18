import AppKit
import BehavioContextCore
import SwiftUI

@MainActor
final class RecordingFeedbackPanelController {
    private let store: RecordingSessionStore
    private let stopRecording: @MainActor () -> Void
    private let panel: NSPanel
    private var compact = UserDefaults.standard.bool(forKey: "compactRecordingBar")
    private var previousPhase = RecordingPhase.idle
    private var previousWarning: String?
    private var dismissalTask: Task<Void, Never>?

    init(
        store: RecordingSessionStore,
        stopRecording: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.stopRecording = stopRecording
        panel = InteractiveRecordingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 68),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        let accessibilityLabel = "UI Screen Context recording controls"
        panel.setAccessibilityLabel(accessibilityLabel)
        panel.contentView = NSHostingView(rootView: RecordingCapsuleView(
            store: store,
            stopRecording: stopRecording,
            dismissFeedback: { [weak store] in
                store?.dismissFeedback()
            },
            setCompact: { [weak self] compact in
                self?.compact = compact
                self?.synchronize()
            },
            selectMicrophone: { [weak store] deviceID in
                Task { await store?.selectMicrophoneDevice(deviceID) }
            }
        ))
    }

    func synchronize() {
        let phaseChanged = store.phase != previousPhase
        let warningChanged = store.hudMessage != previousWarning
        let wasFinalizing = previousPhase == .finalizing
        previousPhase = store.phase
        previousWarning = store.hudMessage

        dismissalTask?.cancel()
        if store.phase == .idle && store.hudMessage == nil {
            if wasFinalizing {
                scheduleDismissal()
            } else {
                panel.orderOut(nil)
            }
            return
        }

        guard let screen = targetScreen else { return }
        let isCompact = compact && store.phase.isRecording
        let width = min(isCompact ? 300 : 940, screen.visibleFrame.width - 32)
        panel.setContentSize(NSSize(width: width, height: isCompact ? 44 : 60))
        position(on: screen)
        panel.ignoresMouseEvents = store.phase == .preparing || store.phase == .finalizing
        panel.orderFrontRegardless()

        if phaseChanged || warningChanged {
            NSAccessibility.post(
                element: panel,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: announcement,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
        if case .failed = store.phase {
            scheduleDismissal()
        }
    }

    private var targetScreen: NSScreen? {
        if let frame = store.selectedCaptureSource?.frame {
            return NSScreen.screens.max {
                $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let sourceFrame = store.selectedCaptureSource?.frame
        let preferredX = sourceFrame.map { $0.midX - panel.frame.width / 2 }
            ?? visible.midX - panel.frame.width / 2
        let x = min(max(preferredX, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        let y: CGFloat
        if let sourceFrame, sourceFrame.maxY + panel.frame.height + 12 <= visible.maxY {
            y = sourceFrame.maxY + 12
        } else {
            y = visible.maxY - panel.frame.height - 12
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismissal() {
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private var announcement: String {
        if let warning = store.hudMessage { return warning }
        return switch store.phase {
        case .preparing: AppLocalization.text("Preparing recording", locale: store.effectiveLocale)
        case .recording: AppLocalization.text("Recording started", locale: store.effectiveLocale)
        case .finalizing: AppLocalization.text("Recording stopped. Creating context.", locale: store.effectiveLocale)
        default: ""
        }
    }
}

private final class InteractiveRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct RecordingCapsuleView: View {
    @AppStorage("compactRecordingBar") private var compact = false
    @Bindable var store: RecordingSessionStore
    let stopRecording: @MainActor () -> Void
    let dismissFeedback: @MainActor () -> Void
    let setCompact: @MainActor (Bool) -> Void
    let selectMicrophone: @MainActor (String) -> Void

    var body: some View {
        Group {
            if store.phase.isRecording {
                recordingContent
            } else {
                statusContent
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thickMaterial)
            if store.phase.isRecording {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.10), .purple.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: store.phase.isRecording
                            ? [.red.opacity(0.65), .purple.opacity(0.40), .white.opacity(0.12)]
                            : [.white.opacity(0.18), .white.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: store.phase.isRecording ? .purple.opacity(0.18) : .black.opacity(0.12), radius: 16, y: 7)
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
    }

    private var recordingContent: some View {
        HStack(spacing: 10) {
            RecordingPulse()

            Text(verbatim: store.elapsedSeconds.recordingDuration) // localization: allow-verbatim numeric timer
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel(AppLocalization.text("Recording started", locale: store.effectiveLocale))

            Button(action: stopRecording) {
                Label {
                    Text(verbatim: stopLabel) // localization: allow-verbatim universal control label
                } icon: {
                    Image(systemName: "stop.fill")
                }
                .labelStyle(RecordingStopLabelStyle(compact: compact))
                .font(.callout.weight(.semibold))
                .frame(width: compact ? 32 : 86, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(StopRecordingButtonStyle())
            .accessibilityLabel("Stop Recording")

            if !compact {
            Divider().frame(height: 28).opacity(0.40)

            Menu {
                ForEach(store.microphones) { microphone in
                    Button {
                        selectMicrophone(microphone.id)
                    } label: {
                        if microphone.id == store.microphoneDeviceID {
                            Label(microphone.name, systemImage: "checkmark")
                        } else {
                            Text(microphone.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                    Text(verbatim: store.selectedMicrophoneName) // localization: allow-verbatim runtime device name
                }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 170)
            .accessibilityLabel(Text(verbatim: microphoneAccessibilityLabel)) // localization: allow-verbatim runtime device name
            .accessibilityHint("Choose a microphone")

            }

            LevelWaveform(level: store.microphoneLevel)
                .frame(width: compact ? 64 : 78, height: 26)

            if !compact {

            Text(store.liveTranscript.isEmpty ? AppLocalization.text("Speak and point to elements in the active window…", locale: store.effectiveLocale) : store.liveTranscript)
                .font(.callout.weight(store.liveTranscriptIsFinal ? .medium : .regular))
                .foregroundStyle(store.liveTranscript.isEmpty || !store.liveTranscriptIsFinal ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
                .animation(.easeOut(duration: 0.18), value: store.liveTranscript)
                .accessibilityLabel(store.liveTranscript.isEmpty ? AppLocalization.text("Waiting for speech", locale: store.effectiveLocale) : store.liveTranscript)

            Label(sourceName, systemImage: "macwindow")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 150)
            }

            if let warning = store.hudMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning)
                    .accessibilityLabel(warning)
            }

            Button {
                compact.toggle()
                setCompact(compact)
            } label: {
                Image(systemName: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(compact ? AppLocalization.text("Expand recording bar", locale: store.effectiveLocale) : AppLocalization.text("Compact recording bar", locale: store.effectiveLocale))
            .accessibilityLabel(compact ? AppLocalization.text("Expand recording bar", locale: store.effectiveLocale) : AppLocalization.text("Compact recording bar", locale: store.effectiveLocale))
        }
    }

    private var statusContent: some View {
        HStack(spacing: 12) {
            if store.phase == .preparing || store.phase == .finalizing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                if let message {
                    Text(verbatim: message) // localization: allow-verbatim runtime progress or error message
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Label(sourceName, systemImage: "macwindow")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if isDismissableStatus {
                Button(action: dismissFeedback) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    private var isDismissableStatus: Bool {
        if case .failed = store.phase { return true }
        return store.phase == .idle && message != nil
    }

    private var statusTitle: String {
        switch store.phase {
        case .preparing: AppLocalization.text("Preparing the active window…", locale: store.effectiveLocale)
        case .finalizing: AppLocalization.text("Creating agent context…", locale: store.effectiveLocale)
        case .failed: AppLocalization.text("Couldn’t start recording", locale: store.effectiveLocale)
        default: "UI Screen Context"
        }
    }

    private var sourceName: String {
        store.activeWindowName ?? store.selectedCaptureSource?.displayName ?? AppLocalization.text("Active window", locale: store.effectiveLocale)
    }

    private var message: String? {
        store.hudMessage ?? store.compilationMessage
    }

    private var stopLabel: String { "Stop" }
    private var microphoneAccessibilityLabel: String { "Microphone: \(store.selectedMicrophoneName)" }
}

private struct RecordingStopLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}

private struct RecordingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.65), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .scaleEffect(isExpanded ? 2.1 : 0.9)
                .opacity(isExpanded ? 0 : 0.9)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.8), radius: 6)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                isExpanded = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StopRecordingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [.red, .pink.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(
                color: .red.opacity(configuration.isPressed ? 0.18 : 0.35),
                radius: configuration.isPressed ? 3 : 8,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct LevelWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<11, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.pink, .purple, .cyan],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: responsiveHeight(index))
                    .opacity(index <= activeBars ? 1 : 0.22)
                    .shadow(
                        color: index <= activeBars ? .purple.opacity(0.45) : .clear,
                        radius: 3
                    )
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.10), value: level)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(min(1, max(0, level)) * 100))%")
    }

    private var activeBars: Int {
        Int((min(1, max(0, level)) * 10).rounded())
    }

    private func responsiveHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [7, 11, 16, 22, 15, 10, 18, 24, 18, 12, 8]
        let energy = min(1, max(0, level))
        return max(4, pattern[index] * energy)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
