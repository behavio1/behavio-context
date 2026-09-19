import AppKit
import BehavioContextCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: RecordingSessionStore
    @Bindable var recordingStorage: RecordingStorageController
    @AppStorage("BehavioContext.showsMenuBarIcon") private var showsMenuBarIcon = true
    @State private var showsAdditionalSettings = false
    let shortcutRecorder: ShortcutRecorder

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ViewThatFits(in: .vertical) {
                settingsContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { settingsContent }
            }

            Divider()

            footer
        }
        .frame(width: 540, height: min(showsAdditionalSettings ? 820 : 740, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .alert(
            store.recordingFailureNotice?.kind == .contextUnavailable ? "Video Saved; Context Unavailable" : "Recording Couldn’t Be Saved",
            isPresented: Binding(
                get: { store.recordingFailureNotice != nil },
                set: { if !$0 { store.dismissRecordingFailureNotice() } }
            ),
            presenting: store.recordingFailureNotice
        ) { notice in
            if let recoveryURL = notice.recoveryURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([recoveryURL])
                    store.dismissRecordingFailureNotice()
                }
            }
            Button("Dismiss", role: .cancel) { store.dismissRecordingFailureNotice() }
        } message: { notice in
            if notice.kind == .contextUnavailable {
                Text("The video was saved and is available in Recordings. Creating the agent context failed. Open the video in Finder.")
            } else if notice.kind == .partialRecordingPreserved {
                Text("UI Screen Context preserved the partial recording. Show it in Finder to see whether it can be played.")
            } else {
                Text("No usable recording was produced. Check your recording settings and try again.")
            }
        }
        .alert("Couldn’t Access Recording Folder", isPresented: Binding(
            get: { recordingStorage.errorMessage != nil },
            set: { if !$0 { recordingStorage.errorMessage = nil } }
        )) {
            Button("Change…") {
                recordingStorage.errorMessage = nil
                recordingStorage.chooseFolder(store: store)
            }
            .disabled(store.configurationIsLocked)
            Button("Dismiss", role: .cancel) { recordingStorage.errorMessage = nil }
        } message: {
            Text(verbatim: recordingStorage.errorMessage ?? "") // localization: allow-verbatim system error
        }
    }

    private var settingsContent: some View {
                VStack(spacing: 14) {
                    CaptureSettingsView(
                        store: store,
                        shortcutRecorder: shortcutRecorder
                    )
                    SpeechSettingsView(store: store).padding(.horizontal, 22)
                    DisclosureGroup("More Settings", isExpanded: $showsAdditionalSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            storageSection
                            Divider()
                            Toggle(isOn: $showsMenuBarIcon) {
                                HStack(spacing: 8) {
                                    MenuBarGlyph(isRecording: store.phase.isRecording)
                                        .accessibilityHidden(true)
                                    Text("Show icon in menu bar")
                                }
                            }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 10)
                    }
                    .disclosureGroupStyle(FullRowDisclosureStyle())
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 18)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recordings and contexts folder", systemImage: "folder")
                .font(.body.weight(.medium))
            if let directory = recordingStorage.directory {
                Text(verbatim: directory.path) // localization: allow-verbatim user-selected filesystem path
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(directory.path)
            }
            Text("New recordings will be saved here. Earlier recordings stay in their original folders.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Change…") { recordingStorage.chooseFolder(store: store) }
                Button("Show in Finder", action: recordingStorage.openFolder)
                    .disabled(recordingStorage.directory == nil)
                Spacer()
                Button("Use Default") {
                    Task { await recordingStorage.restoreDefault(store: store) }
                }
                .disabled(recordingStorage.usesDefault)
            }
            .disabled(store.configurationIsLocked || recordingStorage.isChanging || !store.isInitialized)
        }
        .controlSize(.small)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: productName) // localization: allow-verbatim bundle display name
                    .font(.title2.weight(.semibold))
                Text("Press \(store.globalShortcut.displayName) to start recording. Press it again to stop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Picker("Language", selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .accessibilityLabel("Language")

            Spacer(minLength: 0)

            Link(destination: AppLinks.privacyPolicy) {
                Text("Privacy Policy")
            }
            Link(destination: AppLinks.support) {
                Text("Support")
            }
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .frame(height: 48)
    }

    private var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "UI Screen Context"
    }
}

private extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .polish: "Polski"
        case .spanish: "Español"
        case .german: "Deutsch"
        }
    }
}

private struct FullRowDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation {
                DisclosureGroup(isExpanded: configuration.$isExpanded) { EmptyView() } label: { configuration.label }
            }
            if configuration.isExpanded { configuration.content }
        }
    }
}
