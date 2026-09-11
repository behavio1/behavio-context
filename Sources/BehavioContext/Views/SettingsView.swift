import AppKit
import BehavioContextCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: RecordingSessionStore
    @Bindable var analytics: AnalyticsConsentController
    let shortcutRecorder: ShortcutRecorder

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            CaptureSettingsView(
                store: store,
                shortcutRecorder: shortcutRecorder
            )

            Divider()

            footer
        }
        .frame(width: 540, height: 370)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .alert(
            "Recording Couldn’t Be Saved",
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
            if notice.kind == .partialRecordingPreserved {
                Text("Behavio Context preserved the partial recording. Show it in Finder to see whether it can be played.")
            } else {
                Text("No usable recording was produced. Check your recording settings and try again.")
            }
        }
        .onAppear {
            analytics.capture(.settingsOpened)
        }
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
                    .lineLimit(1)
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
            ?? "Behavio Context"
    }
}

private extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .arabic: "العربية"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        case .vietnamese: "Tiếng Việt"
        case .portugueseBrazil: "Português (Brasil)"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        }
    }
}
