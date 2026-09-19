import AppKit
import BehavioContextCore
import SwiftUI

@MainActor
final class RecordingResultPanelController {
    private static let contentWidth: CGFloat = 820
    private static let fallbackContentHeight: CGFloat = 680
    private static let defaultMediaHeight: CGFloat = 300
    private static let minimumMediaHeight: CGFloat = 160
    private static let verticalScreenMargin: CGFloat = 80
    private let store: RecordingSessionStore
    private let contextReturnController: RecordingContextReturnController
    private let pasteReminderController = PasteReminderPanelController()
    private var presentedResultID: RecordingResult.ID?

    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth,
                height: Self.fallbackContentHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isMovable = true
        return window
    }()

    init(
        store: RecordingSessionStore,
        contextReturnController: RecordingContextReturnController
    ) {
        self.store = store
        self.contextReturnController = contextReturnController
    }

    func present(_ result: RecordingResult) {
        presentedResultID = result.id
        window.title = String(
            localized: "Recordings",
            locale: store.effectiveLocale
        )

        WindowPresentation.afterMenuDismissal { [weak self, result] in
            guard self?.presentedResultID == result.id else { return }
            self?.presentContent(result)
        }
    }

    func presentSelectedRecording() {
        guard let result = store.selectedRecordingResult else { return }
        present(result)
    }

    private func presentContent(_ result: RecordingResult) {
        let visibleHeight = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?
            .visibleFrame.height ?? Self.fallbackContentHeight + Self.verticalScreenMargin
        let maximumContentHeight = max(1, visibleHeight - Self.verticalScreenMargin)

        var mediaHeight = Self.defaultMediaHeight
        var hostingView = makeHostingView(
            result: result,
            mediaHeight: mediaHeight
        )
        var fittingHeight = ceil(hostingView.fittingSize.height)
        let overflow = max(0, fittingHeight - maximumContentHeight)

        if overflow > 0 {
            let mediaReduction = min(
                overflow,
                mediaHeight - Self.minimumMediaHeight
            )
            mediaHeight -= mediaReduction
            hostingView = makeHostingView(
                result: result,
                mediaHeight: mediaHeight
            )
            fittingHeight = ceil(hostingView.fittingSize.height)
        }

        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(
            width: Self.contentWidth,
            height: min(fittingHeight, maximumContentHeight)
        ))
        if !window.isVisible {
            window.center()
        }
        WindowPresentation.bringToFront(window)
    }

    private func makeHostingView(
        result: RecordingResult,
        mediaHeight: CGFloat
    ) -> NSHostingView<RecordingResultView> {
        let hostingView = NSHostingView(
            rootView: RecordingResultView(
                store: store,
                fallbackResult: result,
                mediaHeight: mediaHeight,
                contextReturnController: contextReturnController,
                copiedAndReturned: { [weak self] confirmation, locale in
                    guard let self else { return }
                    let screen = window.screen
                    dismiss()
                    pasteReminderController.show(title: confirmation, locale: locale, on: screen)
                },
                dismiss: { [weak self] in self?.dismiss() }
            )
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func dismiss() {
        window.orderOut(nil)
    }
}
