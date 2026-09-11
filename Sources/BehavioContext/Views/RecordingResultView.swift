import AppKit
import AVKit
import BehavioContextCore
import SwiftUI

struct RecordingResultView: View {
    @Bindable var store: RecordingSessionStore
    let fallbackResult: RecordingResult
    let mediaHeight: CGFloat
    let analytics: AnalyticsConsentController
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
                .disabled(isReturningToApplication)
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
                    RecordingSidebarRow(result: recording)
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
                        Label(copyAndReturnTitle(for: application, content: .video), systemImage: "arrow.uturn.backward")
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
            .accessibilityLabel(Text(verbatim: overflowAccessibilityLabel)) // localization: allow-verbatim Polish v1 overflow label
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
                    Text(verbatim: contextLabel) // localization: allow-verbatim Polish v1 context result label
                        .font(.headline)
                    Text(verbatim: contextDocumentURL?.path ?? result.context) // localization: allow-verbatim local file path
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel(String(localized: "Recording file", locale: locale))
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
                    .help(Text(verbatim: copyContextDocumentLabel)) // localization: allow-verbatim Polish v1 help
                    .accessibilityLabel(Text(verbatim: copyContextDocumentLabel)) // localization: allow-verbatim Polish v1 label
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
                    Label(copyAndReturnTitle(for: application, content: .context), systemImage: "arrow.uturn.backward")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    copyContextToPasteboard()
                } label: {
                    Label("Copy File Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .disabled(isReturningToApplication)
        } else {
            Button {
                copyContextToPasteboard()
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
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
        result.contextDirectoryURL == nil ? "Plik nagrania" : "Kontekst dla agenta · context.md"
    }

    private var overflowAccessibilityLabel: String { "Więcej" }
    private var copyContextDocumentLabel: String { "Kopiuj treść context.md" }

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
        guard pasteboard.setString(contents, forType: .string) else {
            destinationAlert = RecordingContextDestinationAlert(
                title: String(localized: "Couldn’t Copy Context", locale: locale),
                message: String(localized: "Try copying the context again.", locale: locale)
            )
            return
        }
        analytics.capture(.contextCopied)
        showCopyToast(String(localized: "Context copied", locale: locale))
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

        analytics.capture(.videoCopied)
        if showConfirmation {
            showCopyToast(String(localized: "Video copied", locale: locale))
        }
        return true
    }

    private func showVideoCopyError() {
        destinationAlert = RecordingContextDestinationAlert(
            title: String(localized: "Couldn’t Copy Video", locale: locale),
            message: String(localized: "Try copying the video again.", locale: locale)
        )
    }

    @discardableResult
    private func copyContextToPasteboard(showConfirmation: Bool = true) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(result.context, forType: .string) else {
            destinationAlert = RecordingContextDestinationAlert(
                title: String(localized: "Couldn’t Copy Context", locale: locale),
                message: String(localized: "Try copying the context again.", locale: locale)
            )
            return false
        }

        analytics.capture(.contextCopied)
        if showConfirmation {
            showCopyToast(String(localized: "Context copied", locale: locale))
        }
        return true
    }

    private func copyAndReturnTitle(for application: NSRunningApplication, content: CopyContent) -> String {
        String(
            format: content == .video
                ? String(localized: "Copy Video & Return to %@", locale: locale)
                : String(localized: "Copy & Return to %@", locale: locale),
            locale: locale,
            application.localizedName ?? application.bundleIdentifier ?? ""
        )
    }

    private func copyAndReturn(_ content: CopyContent, to application: NSRunningApplication) {
        guard !isReturningToApplication else { return }
        let didCopy: Bool
        let confirmation: String
        switch content {
        case .context:
            didCopy = copyContextToPasteboard(showConfirmation: false)
            confirmation = String(localized: "Context copied", locale: locale)
        case .video:
            didCopy = copyVideoToPasteboard(result.fileURL, showConfirmation: false)
            confirmation = String(localized: "Video copied", locale: locale)
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
        withAnimation(.easeOut(duration: 0.15)) {
            copyToastMessage = message
        }
        copyToastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(.easeIn(duration: 0.15)) {
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

    var body: some View {
        HStack(spacing: 10) {
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
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingPlayerView: NSViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = HoverControlsPlayerView()
        playerView.videoGravity = .resizeAspect
        playerView.player = context.coordinator.player
        context.coordinator.loadAndPlay(fileURL)
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        guard context.coordinator.currentURL != fileURL else { return }
        context.coordinator.loadAndPlay(fileURL)
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        playerView.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        private(set) var currentURL: URL?

        func loadAndPlay(_ fileURL: URL) {
            currentURL = fileURL
            player.replaceCurrentItem(with: AVPlayerItem(url: fileURL))
            player.play()
        }
    }
}

private final class HoverControlsPlayerView: AVPlayerView {
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controlsStyle = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        controlsStyle = .none
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        controlsStyle = .minimal
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        controlsStyle = .none
        super.mouseExited(with: event)
    }
}
