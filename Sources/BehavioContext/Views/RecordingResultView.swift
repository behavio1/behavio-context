import AppKit
import AVKit
import BehavioContextCore
import SwiftUI

struct RecordingResultView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: RecordingSessionStore
    let fallbackResult: RecordingResult
    let mediaHeight: CGFloat
    let contextReturnController: RecordingContextReturnController
    let copiedAndReturned: @MainActor (String, Locale) -> Void
    let dismiss: @MainActor () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var copyToastMessage: String?
    @State private var copyToastDismissTask: Task<Void, Never>?
    @State private var isConfirmingDeletion = false
    @State private var isDeletingRecording = false
    @State private var destinationAlert: RecordingContextDestinationAlert?
    @State private var isReturningToApplication = false
    @State private var contextDocumentText: String?

    private enum CopyContent {
        case context, video
    }

    var body: some View {
        NavigationSplitView {
            recordingSidebar
                .disabled(isReturningToApplication || isDeletingRecording || isConfirmingDeletion)
                .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 210)
        } detail: {
            recordingDetail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 820)
        .overlay(alignment: .top) {
            if let copyToastMessage {
                Label(copyToastMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onDisappear {
            copyToastDismissTask?.cancel()
        }
        .task(id: result.id) {
            loadContextDocument()
        }
        .confirmationDialog(
            "Delete Recording?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete Recording", role: .destructive) {
                Task {
                    isDeletingRecording = true
                    let didDelete = await store.deleteSelectedRecording()
                    isDeletingRecording = false
                    if didDelete, store.recordingResults.isEmpty {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently deletes the recording.")
        }
        .alert(item: $destinationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("Done"))
            )
        }
        .environment(\.locale, locale)
    }

    private var recordingSidebar: some View {
        List(selection: recordingSelection) {
            Section("Recordings") {
                ForEach(store.recordingResults.reversed()) { recording in
                    RecordingSidebarRow(result: recording) {
                        store.selectRecording(recording.id)
                        isConfirmingDeletion = true
                    }
                        .tag(recording.id)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Recordings")
    }

    private var recordingSelection: Binding<RecordingResult.ID?> {
        Binding(
            get: { store.selectedRecordingID },
            set: { id in
                guard let id else { return }
                store.selectRecording(id)
            }
        )
    }

    private var recordingDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            recordingHeader

            RecordingPlayerView(fileURL: result.fileURL)
                .frame(width: 588, height: mediaHeight)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.10),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10),
                    radius: 14,
                    y: 7
                )

            contextCard
        }
        .padding(20)
        .frame(width: 636)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var recordingHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    result.recordedAt,
                    format: .dateTime
                        .year()
                        .month(.wide)
                        .day()
                )
                .font(.title3.weight(.semibold))

                Text(result.recordedAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    copyVideoToPasteboard(result.fileURL)
                } label: {
                    Label("Copy Video", systemImage: "doc.on.doc")
                }

                if let application = contextReturnController.destination(for: result.id) {
                    Button {
                        copyAndReturn(.video, to: application)
                    } label: {
                        Label("Copy Video & Return", systemImage: "arrow.uturn.backward")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
                .disabled(isDeletingRecording || isReturningToApplication)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: overflowAccessibilityLabel)) // localization: allow-verbatim localized overflow label
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if result.contextDirectoryURL == nil {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: AppResourceBundle.image(named: "ContextGlyph"))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: contextLabel) // localization: allow-verbatim localized context result label
                        .font(.headline)
                    Text(verbatim: contextDocumentURL?.path ?? result.context) // localization: allow-verbatim local file path
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel(AppLocalization.text("Recording file", locale: locale))
                }

                Spacer(minLength: 0)

                if let contextDocumentText, !contextDocumentText.isEmpty {
                    Button {
                        copyContextDocumentToPasteboard(contextDocumentText)
                    } label: {
                        Image(nsImage: AppResourceBundle.image(named: "CopyGlyph"))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help(Text(verbatim: copyContextDocumentLabel)) // localization: allow-verbatim localized help
                    .accessibilityLabel(Text(verbatim: copyContextDocumentLabel)) // localization: allow-verbatim localized label
                }
            }

            if result.contextDirectoryURL != nil {
                contextDocumentPreview
            }

            contextActions
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var contextDocumentPreview: some View {
        if let contextDocumentText {
            ScrollView {
                Text(verbatim: contextDocumentText.isEmpty ? result.context : contextDocumentText) // localization: allow-verbatim agent context file contents
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 116)
            .background(Color.black.opacity(colorScheme == .dark ? 0.20 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 116)
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        if let application = contextReturnController.destination(for: result.id) {
            HStack(spacing: 8) {
                Button {
                    copyAndReturn(.context, to: application)
                } label: {
                    Label("Copy Path & Return", systemImage: "arrow.uturn.backward")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    copyContextToPasteboard()
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .disabled(isReturningToApplication)
        } else {
            Button {
                copyContextToPasteboard()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReturningToApplication)
        }
    }

    private var result: RecordingResult {
        store.selectedRecordingResult ?? fallbackResult
    }

    private var locale: Locale { store.effectiveLocale }

    private var contextLabel: String {
        result.contextDirectoryURL == nil ? AppLocalization.text("Recording file", locale: locale) : AppLocalization.text("Agent context", locale: locale)
    }

    private var overflowAccessibilityLabel: String { AppLocalization.text("More", locale: locale) }
    private var copyContextDocumentLabel: String { AppLocalization.text("Copy Context Text", locale: locale) }

    private var contextDocumentURL: URL? {
        result.contextDirectoryURL?.appendingPathComponent("context.md")
    }

    private func loadContextDocument() {
        contextDocumentText = nil
        guard let contextDocumentURL else {
            contextDocumentText = ""
            return
        }
        contextDocumentText = (try? String(contentsOf: contextDocumentURL, encoding: .utf8)) ?? ""
    }

    private func copyContextDocumentToPasteboard(_ contents: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copiedText = result.contextDirectoryURL.map {
            AgentContextPackageWriter.clipboardText(contents, directoryURL: $0)
        } ?? contents
        guard pasteboard.setString(copiedText, forType: .string) else {
            destinationAlert = RecordingContextDestinationAlert(
                title: AppLocalization.text("Couldn’t Copy Context", locale: locale),
                message: AppLocalization.text("Try copying the context again.", locale: locale)
            )
            return
        }
        showCopyToast(AppLocalization.text("Context text copied", locale: locale))
    }

    @discardableResult
    private func copyVideoToPasteboard(_ fileURL: URL, showConfirmation: Bool = true) -> Bool {
        let item = NSPasteboardItem()
        let pasteboard = NSPasteboard.general
        guard item.setString(fileURL.absoluteString, forType: .fileURL) else {
            showVideoCopyError()
            return false
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            showVideoCopyError()
            return false
        }

        if showConfirmation {
            showCopyToast(AppLocalization.text("Video copied", locale: locale))
        }
        return true
    }

    private func showVideoCopyError() {
        destinationAlert = RecordingContextDestinationAlert(
            title: AppLocalization.text("Couldn’t Copy Video", locale: locale),
            message: AppLocalization.text("Try copying the video again.", locale: locale)
        )
    }

    @discardableResult
    private func copyContextToPasteboard(showConfirmation: Bool = true) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(result.context, forType: .string) else {
            destinationAlert = RecordingContextDestinationAlert(
                title: AppLocalization.text("Couldn’t Copy Context", locale: locale),
                message: AppLocalization.text("Try copying the context again.", locale: locale)
            )
            return false
        }

        if showConfirmation {
            showCopyToast(AppLocalization.text("Path copied", locale: locale))
        }
        return true
    }

    private func copyAndReturn(_ content: CopyContent, to application: NSRunningApplication) {
        guard !isReturningToApplication else { return }
        let didCopy: Bool
        let confirmation: String
        switch content {
        case .context:
            didCopy = copyContextToPasteboard(showConfirmation: false)
            confirmation = AppLocalization.text("Path copied", locale: locale)
        case .video:
            didCopy = copyVideoToPasteboard(result.fileURL, showConfirmation: false)
            confirmation = AppLocalization.text("Video copied", locale: locale)
        }
        guard didCopy else { return }
        isReturningToApplication = true
        Task { @MainActor in
            let didActivate = await contextReturnController.activate(application)
            isReturningToApplication = false
            if didActivate {
                copiedAndReturned(confirmation, locale)
            } else {
                destinationAlert = RecordingContextDestinationAlert(
                    title: confirmation,
                    message: String(
                        localized: "Couldn’t return to the original app. Switch to your destination and press ⌘V to paste.",
                        locale: locale
                    )
                )
            }
        }
    }

    private func showCopyToast(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )

        copyToastDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            copyToastMessage = message
        }
        copyToastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) {
                copyToastMessage = nil
            }
        }
    }

}

private struct RecordingContextDestinationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RecordingSidebarRow: View {
    let result: RecordingResult
    let requestDeletion: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: AppResourceBundle.image(named: "CaptureGlyph"))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    result.recordedAt,
                    format: .dateTime
                        .year()
                        .month(.abbreviated)
                        .day()
                )
                .fontWeight(.medium)
                .lineLimit(1)

                Text(result.recordedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: requestDeletion) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete Recording")
            .accessibilityLabel("Delete Recording")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct RecordingPlayerView: NSViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        playerView.player = context.coordinator.player
        context.coordinator.load(fileURL)
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        guard context.coordinator.currentURL != fileURL else { return }
        context.coordinator.load(fileURL)
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        playerView.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        private(set) var currentURL: URL?

        func load(_ fileURL: URL) {
            currentURL = fileURL
            player.replaceCurrentItem(with: AVPlayerItem(url: fileURL))
            player.pause()
        }
    }
}
