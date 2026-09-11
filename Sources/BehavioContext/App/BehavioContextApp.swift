import BehavioContextCore
import SwiftUI

@main
struct BehavioContextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: appDelegate.store,
                toggleRecording: appDelegate.toggleRecording,
                openRecordings: appDelegate.showRecordings,
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
                analytics: appDelegate.analytics,
                shortcutRecorder: appDelegate.shortcutRecorder
            )
            .background(WindowAccessor(onWindowAttached: appDelegate.registerSettingsWindow))
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
