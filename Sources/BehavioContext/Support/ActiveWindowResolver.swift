import AppKit
import CoreGraphics
import BehavioContextCore

struct ActiveWindowHint: Sendable {
    let processIdentifier: pid_t
    let windowID: UInt32?
    let applicationName: String
}

enum ActiveWindowResolverError: Error, LocalizedError {
    case noExternalApplication
    case noRecordableWindow(String)

    var errorDescription: String? {
        switch self {
        case .noExternalApplication:
            "No active application is available to record."
        case let .noRecordableWindow(applicationName):
            "No visible window is available to record: \(applicationName)"
        }
    }
}

actor ActiveWindowResolver {
    private let catalog: ScreenCaptureKitSourceCatalog
    private let ownBundleIdentifier: String

    init(ownBundleIdentifier: String) {
        self.ownBundleIdentifier = ownBundleIdentifier
        catalog = ScreenCaptureKitSourceCatalog(bundleIdentifier: ownBundleIdentifier)
    }

    @MainActor
    static func captureHint(ownBundleIdentifier: String) throws -> ActiveWindowHint {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != ownBundleIdentifier else {
            throw ActiveWindowResolverError.noExternalApplication
        }
        let processIdentifier = application.processIdentifier
        let windowID = topmostWindowID(processIdentifier: processIdentifier)
        return ActiveWindowHint(
            processIdentifier: processIdentifier,
            windowID: windowID,
            applicationName: application.localizedName ?? "application"
        )
    }

    func resolve(_ hint: ActiveWindowHint) async throws -> CaptureSource {
        let sources = try await catalog.sources()
        let windows = sources.compactMap { source -> WindowSource? in
            guard case let .window(window) = source,
                  window.processIdentifier == hint.processIdentifier else { return nil }
            return window
        }
        let match = hint.windowID.flatMap { id in windows.first { $0.windowID == id } }
        guard let match else {
            throw ActiveWindowResolverError.noRecordableWindow(hint.applicationName)
        }
        return .window(match)
    }

    @MainActor
    private static func topmostWindowID(processIdentifier: pid_t) -> UInt32? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width >= 160,
                  bounds.height >= 90,
                  let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
            return number.uint32Value
        }
        return nil
    }
}
