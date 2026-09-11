import AppKit
import BehavioContextCore
import SwiftUI

@MainActor
final class RecordingFeedbackPanelController {
    private let store: RecordingSessionStore
    private let stopRecording: @MainActor () -> Void
    private let panel: NSPanel
    private var previousPhase = RecordingPhase.idle
    private var previousWarning: String?
    private var dismissalTask: Task<Void, Never>?

    init(
        store: RecordingSessionStore,
        stopRecording: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.stopRecording = stopRecording
        panel = NSPanel(
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        let accessibilityLabel = "Behavio Context recording controls"
        panel.setAccessibilityLabel(accessibilityLabel)
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
        let width = min(940, max(680, screen.visibleFrame.width - 32))
        panel.setContentSize(NSSize(width: width, height: 68))
        position(on: screen)
        panel.ignoresMouseEvents = store.phase == .preparing || store.phase == .finalizing
        panel.contentView = NSHostingView(rootView: RecordingCapsuleView(
            phase: store.phase,
            elapsedSeconds: store.elapsedSeconds,
            microphoneLevel: store.microphoneLevel,
            transcript: store.liveTranscript,
            transcriptIsFinal: store.liveTranscriptIsFinal,
            microphoneName: store.selectedMicrophoneName,
            microphoneDeviceID: store.microphoneDeviceID,
            microphones: store.microphones,
            sourceName: store.selectedCaptureSource?.displayName ?? "Aktywne okno",
            message: store.hudMessage ?? store.compilationMessage,
            locale: store.effectiveLocale,
            isRightToLeft: store.usesRightToLeftLayout,
            stopRecording: stopRecording,
            dismissFeedback: { [weak store = self.store] in
                store?.dismissFeedback()
            },
            selectMicrophone: { [weak store = self.store] deviceID in
                Task { await store?.selectMicrophoneDevice(deviceID) }
            }
        ))
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
        case .preparing: "Przygotowuję nagrywanie"
        case .recording: "Nagrywanie rozpoczęte"
        case .finalizing: "Nagrywanie zatrzymane. Tworzę kontekst."
        default: ""
        }
    }
}

private struct RecordingCapsuleView: View {
    let phase: RecordingPhase
    let elapsedSeconds: TimeInterval
    let microphoneLevel: Double
    let transcript: String
    let transcriptIsFinal: Bool
    let microphoneName: String
    let microphoneDeviceID: String?
    let microphones: [CaptureDeviceOption]
    let sourceName: String
    let message: String?
    let locale: Locale
    let isRightToLeft: Bool
    let stopRecording: @MainActor () -> Void
    let dismissFeedback: @MainActor () -> Void
    let selectMicrophone: @MainActor (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if phase.isRecording {
                recordingContent
            } else {
                statusContent
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .environment(\.locale, locale)
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var recordingContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.75), radius: reduceMotion ? 3 : 7)

            Text(verbatim: elapsedSeconds.recordingDuration) // localization: allow-verbatim numeric timer
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel("Recording started")

            Button(action: stopRecording) {
                Label {
                    Text(verbatim: stopLabel) // localization: allow-verbatim universal control label
                } icon: {
                    Image(systemName: "stop.fill")
                }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red)
            .background(Color.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.55), lineWidth: 1)
            }
            .accessibilityLabel("Stop Recording")

            Divider().frame(height: 28).opacity(0.40)

            Menu {
                ForEach(microphones) { microphone in
                    Button {
                        selectMicrophone(microphone.id)
                    } label: {
                        if microphone.id == microphoneDeviceID {
                            Label(microphone.name, systemImage: "checkmark")
                        } else {
                            Text(microphone.name)
                        }
                    }
                }
            } label: {
                Label(microphoneName, systemImage: "mic.fill")
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

            LevelWaveform(level: microphoneLevel)
                .frame(width: 64, height: 24)

            Text(transcript.isEmpty ? "Mów i wskazuj elementy w aktywnym oknie…" : transcript)
                .font(.callout.weight(transcriptIsFinal ? .medium : .regular))
                .foregroundStyle(transcript.isEmpty || !transcriptIsFinal ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(transcript.isEmpty ? "Oczekiwanie na mowę" : transcript)

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
    }

    private var statusContent: some View {
        HStack(spacing: 12) {
            if phase == .preparing || phase == .finalizing {
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
        if case .failed = phase { return true }
        return phase == .idle && message != nil
    }

    private var statusTitle: String {
        switch phase {
        case .preparing: "Przygotowuję aktywne okno…"
        case .finalizing: "Tworzę lekki kontekst dla agenta…"
        case .failed: "Nie udało się rozpocząć"
        default: "Behavio Context"
        }
    }

    private var stopLabel: String { "Stop" }
    private var microphoneAccessibilityLabel: String { "Microphone: \(microphoneName)" }
}

private struct LevelWaveform: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<11, id: \.self) { index in
                Capsule()
                    .fill(index <= activeBars ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: activeBars)
    }

    private var activeBars: Int {
        Int((min(1, max(0, level)) * 10).rounded())
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [7, 11, 16, 22, 15, 10, 18, 24, 18, 12, 8]
        return pattern[index]
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
