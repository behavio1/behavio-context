import AppKit
import BehavioContextCore
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: RecordingSessionStore
    let toggleRecording: () -> Void
    let openRecordings: () -> Void
    let recordingStorage: RecordingStorageController
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            header

            primaryAction

            HStack(spacing: 8) {
                Button(action: openRecordings) {
                    Label("Recordings", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.recordingResults.isEmpty)

                Button(action: openSettings) {
                    Label("Settings…", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            Button(action: recordingStorage.openFolder) {
                Label("Open Recordings Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(recordingStorage.directory == nil || recordingStorage.isChanging)

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 310)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: productName) // localization: allow-verbatim bundle display name
                    .font(.headline)
                Text(verbatim: statusSummary) // localization: allow-verbatim runtime status
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if store.phase.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .shadow(color: .red.opacity(0.65), radius: 4)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if store.phase == .finalizing {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Finalizing Recording…")
                    .fontWeight(.medium)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Button(action: toggleRecording) {
                HStack(spacing: 9) {
                    if store.phase.isRecording || store.phase == .preparing {
                        Image(systemName: "stop.fill")
                    } else {
                        Image(nsImage: AppResourceBundle.image(named: "CaptureGlyph"))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    Text(store.phase.isRecording || store.phase == .preparing ? "Stop Recording" : "Start Recording")
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Text(verbatim: store.globalShortcut.displayName) // localization: allow-verbatim shortcut glyphs
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.phase.isRecording || store.phase == .preparing ? .red : .accentColor)
            .controlSize(.large)
            .disabled(!store.isInitialized || recordingStorage.isChanging)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppResourceBundle.image(named: "MicrophoneGlyph"))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(verbatim: store.selectedMicrophoneName) // localization: allow-verbatim runtime device name
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Menu {
                Button("Quit UI Screen Context") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: overflowAccessibilityLabel)) // localization: allow-verbatim localized overflow label
        }
    }

    private var statusSummary: String {
        if store.phase.isRecording || store.phase == .finalizing {
            return store.elapsedSeconds.recordingDuration
        }
        if store.phase == .preparing {
            return AppLocalization.text("Preparing…", locale: store.effectiveLocale)
        }
        return store.globalShortcut.displayName
    }

    private var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "UI Screen Context"
    }

    private var overflowAccessibilityLabel: String { AppLocalization.text("More", locale: store.effectiveLocale) }
}

struct RecordingStatusLabel: View {
    let store: RecordingSessionStore

    var body: some View {
        HStack(spacing: 4) {
            MenuBarGlyph(isRecording: store.phase.isRecording)
            if store.phase.isRecording || store.phase == .finalizing {
                Text(store.elapsedSeconds.recordingDuration)
                    .monospacedDigit()
            } else if store.phase == .preparing {
                Text("Preparing…")
            }
        }
        .accessibilityLabel("UI Screen Context menu")
        .accessibilityValue(store.phase.isRecording ? "Recording started" : (store.phase == .finalizing ? "Finalizing Recording…" : "Ready"))
    }
}

extension TimeInterval {
    var recordingDuration: String {
        let seconds = max(0, Int(self))
        if seconds < 3_600 {
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
