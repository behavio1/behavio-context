import AppKit
import BehavioContextCore
import SwiftUI

struct SpeechSettingsView: View {
    @Bindable var store: RecordingSessionStore
    @State private var confirmDownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Speech Recognition", systemImage: "waveform")
                .font(.body.weight(.medium))
            Picker("Spoken language", selection: $store.speech.language) {
                ForEach(SpeechLanguage.allCases) { language in
                    Text(verbatim: language.name).tag(language) // localization: allow-verbatim native language name
                }
            }
            Picker("Recognition engine", selection: $store.speech.engine) {
                Text("Apple · On this Mac").tag(SpeechEngine.apple)
                Text("Whisper Small · Local").tag(SpeechEngine.whisperSmall)
                Text("Whisper Large v3 Turbo · Local").tag(SpeechEngine.whisperTurbo)
            }
            Text("Choose the language you speak. This does not change the app language.")
                .font(.caption).foregroundStyle(.secondary)
            readiness
            if store.speech.engine != .apple {
                Text("Whisper transcribes after you stop recording. Audio stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.speechModelInstaller.downloading != nil {
                    if store.speechModelInstaller.isImporting {
                        ProgressView("Checking local model…")
                    } else {
                        ProgressView(value: store.speechModelInstaller.progress)
                    }
                    Button("Cancel") { store.speechModelInstaller.cancel() }
                } else if store.speechReadiness == .whisperModelMissing {
                    Button("Download Model…") { confirmDownload = true }
                }
                if store.speechModelInstaller.downloading == nil {
                    Button("Use Existing Model…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.begin { response in
                            guard response == .OK, let url = panel.url else { return }
                            store.speechModelInstaller.importModel(from: url, engine: store.speech.engine) { store.refreshSpeechReadiness() }
                        }
                    }
                    Text("Choose a model file or folder. A local copy is verified and stored for this app; no download is needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.speechModelInstaller.error {
                    Text(AppLocalization.text(error, locale: store.effectiveLocale))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .controlSize(.small)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(store.configurationIsLocked)
        .task { store.refreshSpeechReadiness() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshSpeechReadiness() }
        .confirmationDialog("Download a local speech model?", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("Download Model") {
                store.speechModelInstaller.download(store.speech.engine) { store.refreshSpeechReadiness() }
            }
        } message: {
            Text(LocalizedStringKey(store.speech.engine == .whisperSmall
                 ? "Downloads about 488 MB from Hugging Face. The model runs locally; your recordings are never uploaded."
                 : "Downloads about 1.63 GB from Hugging Face. The model runs locally; your recordings are never uploaded."))
        }
    }

    @ViewBuilder private var readiness: some View {
        if store.speechReadiness == .ready {
            Label("Ready for local recognition", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else if store.speechReadiness == .appleModelMissing {
            Text("Apple’s offline model is unavailable for this language. In System Settings → Keyboard → Dictation, add the language and allow any offered download. Then check again. If it remains unavailable, use local Whisper.")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Open Dictation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Dictation")!)
                }
                Button("Check Again") { store.refreshSpeechReadiness() }
            }
        } else if store.speechReadiness == .permissionDenied {
            Text("Allow Speech Recognition for this app in System Settings → Privacy & Security.")
                .font(.caption).foregroundStyle(.orange)
            Button("Open Speech Permissions") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
            }
        } else if store.speechReadiness == .permissionRequired {
            Text("macOS will ask for speech recognition permission when you start recording.")
                .font(.caption).foregroundStyle(.secondary)
        } else if store.speechReadiness == .whisperRuntimeMissing {
            Text("The local Whisper runtime is missing. Reinstall the app.")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

struct SpokenLanguageMenu: View {
    @Bindable var store: RecordingSessionStore
    @State private var showGuidance = false
    var body: some View {
        Menu {
            ForEach(SpeechLanguage.allCases) { language in
                Button {
                    Task {
                        await store.selectSpeechLanguage(language)
                        showGuidance = store.speechReadiness != .ready && store.speechReadiness != .permissionRequired
                    }
                } label: {
                    if language == store.speech.language {
                        Label(language.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: language.name) // localization: allow-verbatim native language name
                    }
                }
            }
            Divider()
            Text("Changes apply to the whole recording.")
        } label: {
            Text(verbatim: store.speech.language.code.uppercased()) // localization: allow-verbatim ISO language code
                .font(.caption.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Spoken language")
        .help("Spoken language")
        .popover(isPresented: $showGuidance) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Speech setup required").font(.headline)
                Text("This language is not ready for local recognition with the selected engine. Open Speech Recognition settings to configure Apple or download a Whisper model. Your video will still be saved.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("OK") { showGuidance = false }
            }
            .padding().frame(width: 310)
            .environment(\.locale, store.effectiveLocale)
        }
    }
}
