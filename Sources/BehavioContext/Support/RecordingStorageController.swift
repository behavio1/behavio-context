import AppKit
import BehavioContextCore
import Observation

@MainActor
@Observable
final class RecordingStorageController {
    let library: RecordingLibrary
    private(set) var directory: URL?
    private(set) var usesDefault = true
    private(set) var isChanging = false
    var errorMessage: String?

    init(library: RecordingLibrary) { self.library = library }

    func refresh() async {
        do {
            directory = try await library.recordingDirectory()
            usesDefault = await library.usesDefaultDirectory()
        } catch {
            directory = nil
            errorMessage = error.localizedDescription
        }
    }

    func chooseFolder(store: RecordingSessionStore) {
        guard !store.configurationIsLocked, !isChanging else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        panel.message = AppLocalization.text("Recordings and contexts folder", locale: store.effectiveLocale)
        isChanging = true
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url, !store.configurationIsLocked else {
                self.isChanging = false
                return
            }
            Task { @MainActor in
                defer { self.isChanging = false }
                do {
                    try await self.library.selectDirectory(url)
                    await self.refresh()
                    await store.reloadRecordingHistory()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func restoreDefault(store: RecordingSessionStore) async {
        guard !store.configurationIsLocked, !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        do {
            try await library.useDefaultDirectory()
            await refresh()
            await store.reloadRecordingHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFolder() {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(directory) else {
                throw CocoaError(.fileReadUnknown)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
