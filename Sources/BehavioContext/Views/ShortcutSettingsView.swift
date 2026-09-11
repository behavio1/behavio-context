import BehavioContextCore
import SwiftUI

struct ShortcutSettingsView: View {
    let store: RecordingSessionStore
    let recorder: ShortcutRecorder

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppResourceBundle.image(named: "ShortcutGlyph"))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .shadow(color: .blue.opacity(0.20), radius: 5, y: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Global shortcut")
                    .font(.body.weight(.medium))
                if recorder.isRecording {
                    Text("Press a key with ⌘, ⌃, or ⌥. Press Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(recorder.needsModifier ? Color.orange : .secondary)
                } else if store.shortcutRegistrationFailed {
                    Text("This shortcut is unavailable. Choose a different combination.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start(completion: store.updateGlobalShortcut)
                }
            } label: {
                Text(recorder.isRecording ? "Cancel" : store.globalShortcut.displayName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .monospaced()
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(recorder.isRecording ? "Cancel" : "Change shortcut")
            .accessibilityValue(store.globalShortcut.displayName)
            .help("Click to record a new shortcut.")

            if store.globalShortcut != .defaultShortcut || recorder.isRecording {
                Button {
                    recorder.stop()
                    store.updateGlobalShortcut(.defaultShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(recorder.isRecording)
                .accessibilityLabel("Reset")
            }
        }
        .padding(.vertical, 12)
        .disabled(!store.isInitialized)
        .onDisappear { recorder.stop() }
    }
}
