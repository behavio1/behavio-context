import BehavioContextCore
import SwiftUI

struct CaptureSettingsView: View {
    @Bindable var store: RecordingSessionStore

    let shortcutRecorder: ShortcutRecorder

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                sourceRow

                Divider().padding(.leading, 48)

                microphoneRow

                Divider().padding(.leading, 48)

                ShortcutSettingsView(store: store, recorder: shortcutRecorder)
            }
            .padding(.horizontal, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            if store.screenCaptureAccessDenied {
                permissionCallout
            } else if let message = store.hudMessage {
                warningCallout(message)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .disabled(!store.isInitialized)
        .task {
            guard !store.configurationIsLocked else { return }
            await store.refreshSources()
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 14) {
            SettingsGlyph(symbol: "macwindow", tint: .cyan)

            VStack(alignment: .leading, spacing: 3) {
                Text("Recording source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: activeWindowTitle) // localization: allow-verbatim runtime active-window title
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(verbatim: activeWindowHelp) // localization: allow-verbatim localized active-window explanation
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .opacity(store.screenCaptureAccessDenied ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
    }

    private var microphoneRow: some View {
        HStack(spacing: 14) {
            SettingsGlyph(symbol: "mic.fill", tint: .mint)

            Text("Microphone")
                .font(.body.weight(.medium))

            Spacer(minLength: 8)

            if store.capturesMicrophone {
                Picker("Microphone", selection: Binding(
                    get: { store.microphoneDeviceID },
                    set: { id in Task { await store.selectMicrophoneDevice(id) } }
                )) {
                    ForEach(store.microphones) { microphone in
                        Text(microphone.name).tag(Optional(microphone.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            Toggle("Microphone", isOn: Binding(
                get: { store.capturesMicrophone },
                set: { enabled in Task { await store.setMicrophoneEnabled(enabled) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 12)
        .disabled(store.configurationIsLocked)
    }

    private var permissionCallout: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording source")
                    .font(.callout.weight(.semibold))
                Text(verbatim: permissionSummary) // localization: allow-verbatim localized permission explanation
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Allow Screen Recording…", action: store.requestScreenCaptureAccess)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func warningCallout(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(verbatim: message) // localization: allow-verbatim runtime error description
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: store.clearWarning) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activeWindowTitle: String {
        if store.phase.locksConfiguration, let source = store.selectedCaptureSource {
            return store.activeWindowName ?? source.displayName
        }
        return AppLocalization.text("Active window", locale: store.effectiveLocale)
    }

    private var activeWindowHelp: String {
        AppLocalization.text("Follows the active window when you switch apps or windows. The whole display is never recorded.", locale: store.effectiveLocale)
    }

    private var permissionSummary: String {
        AppLocalization.text("Requires Screen Recording permission.", locale: store.effectiveLocale)
    }
}
