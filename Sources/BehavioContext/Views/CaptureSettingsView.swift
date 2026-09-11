import BehavioContextCore
import SwiftUI

struct CaptureSettingsView: View {
    @Bindable var store: RecordingSessionStore

    let shortcutRecorder: ShortcutRecorder
    let editWebcamLayout: @MainActor () -> Void

    var body: some View {
        Form {
            ShortcutSettingsView(store: store, recorder: shortcutRecorder)

            if store.phase.locksConfiguration {
                Section {
                    if store.phase == .preparing {
                        ProgressView("Preparing…")
                    } else {
                        HStack {
                            Text(store.phase.isRecording ? "Stop Recording" : "Finalizing Recording…")
                            Spacer()
                            Text(store.elapsedSeconds.recordingDuration).monospacedDigit()
                        }
                    }
                }
            }

            Section("Recording source") {
                HStack(alignment: .top, spacing: 12) {
                    Label("Windows", systemImage: "macwindow")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: activeWindowTitle) // localization: allow-verbatim Polish v1 active-window title
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: activeWindowHelp) // localization: allow-verbatim Polish v1 active-window explanation
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    Label("Screens", systemImage: "display")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    Text(verbatim: screensExcludedHelp) // localization: allow-verbatim Polish v1 full-screen privacy explanation
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.screenCaptureAccessDenied {
                    Button("Allow Screen Recording…", action: store.requestScreenCaptureAccess)
                }
            }
            .disabled(store.configurationIsLocked)

            Section("Audio") {
                Toggle("Microphone", isOn: Binding(
                    get: { store.capturesMicrophone },
                    set: { enabled in Task { await store.setMicrophoneEnabled(enabled) } }
                ))
                if store.capturesMicrophone {
                    Picker("Microphone", selection: Binding(
                        get: { store.microphoneDeviceID },
                        set: { id in Task { await store.selectMicrophoneDevice(id) } }
                    )) {
                        ForEach(store.microphones) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .disabled(store.configurationIsLocked)

            if let message = store.hudMessage {
                Section {
                    Label {
                        Text(verbatim: message) // localization: allow-verbatim runtime error description
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Button("Dismiss", action: store.clearWarning)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!store.isInitialized)
        .task {
            guard !store.configurationIsLocked else { return }
            await store.refreshSources()
        }
    }

    private var activeWindowTitle: String {
        if store.phase.locksConfiguration, let source = store.selectedCaptureSource {
            return source.displayName
        }
        return "Aktywne okno przy starcie"
    }

    private var activeWindowHelp: String {
        "Behavio Context zamraża okno, które jest na wierzchu po naciśnięciu ⌃⌘R. Nigdy nie przełącza się na cały monitor."
    }

    private var screensExcludedHelp: String {
        "Cały monitor nie jest przechwytywany ani zapisywany w pakiecie agenta."
    }
}
