import BehavioContextCore
import SwiftUI

@main
struct BehavioContextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("BehavioContext.showsMenuBarIcon") private var showsMenuBarIcon = true

    var body: some Scene {
        // SwiftUI can write insertion state during scene updates. Persist only
        // the user's Settings toggle, avoiding a scene/UserDefaults feedback loop.
        MenuBarExtra(isInserted: .constant(showsMenuBarIcon)) {
            MenuBarContentView(
                store: appDelegate.store,
                toggleRecording: appDelegate.toggleRecording,
                openRecordings: appDelegate.showRecordings,
                recordingStorage: appDelegate.recordingStorage,
                openSettings: appDelegate.openSettings
            )
            .environment(\.locale, appDelegate.store.effectiveLocale)
            .environment(
                \.layoutDirection,
                appDelegate.store.usesRightToLeftLayout ? .rightToLeft : .leftToRight
            )
        } label: {
            RecordingStatusLabel(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                store: appDelegate.store,
                recordingStorage: appDelegate.recordingStorage,
                shortcutRecorder: appDelegate.shortcutRecorder
            )
            .background(WindowAccessor(onWindowAttached: appDelegate.registerSettingsWindow))
            .onChange(of: appDelegate.store.language) { appDelegate.updateSettingsTitle() }
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandMenu(AppLocalization.text("Recording", locale: appDelegate.store.effectiveLocale)) {
                Button(AppLocalization.text(appDelegate.store.phase.isRecording ? "Stop Recording" : "Start Recording", locale: appDelegate.store.effectiveLocale)) {
                    appDelegate.toggleRecordingFromAppMenu()
                }
                .disabled(!appDelegate.store.isInitialized || appDelegate.store.phase == .finalizing)
                Button(AppLocalization.text("Recordings", locale: appDelegate.store.effectiveLocale)) { appDelegate.showRecordings() }
            }
        }
    }
}
