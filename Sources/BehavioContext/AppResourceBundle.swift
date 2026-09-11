import AppKit
import Foundation

enum AppResourceBundle {
    static let current: Bundle = {
        let bundleName = "BehavioContext_BehavioContext.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return Bundle.main
    }()

    static func image(named name: String) -> NSImage {
        guard
            let url = current.url(forResource: name, withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        return image
    }
}
