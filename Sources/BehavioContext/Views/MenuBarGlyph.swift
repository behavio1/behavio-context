import AppKit
import SwiftUI

/// A template image works in NSStatusItem as well as in the Settings preview.
/// MenuBarExtra extracts images from its label; arbitrary SwiftUI paths can disappear.
struct MenuBarGlyph: View {
    var isRecording = false

    var body: some View {
        Image(nsImage: Self.image)
            .renderingMode(.template)
            .foregroundStyle(isRecording ? Color.red : Color.primary)
            .frame(width: 21, height: 21)
    }

    private static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 21, height: 21), flipped: true) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 12, y: 3))
            path.line(to: NSPoint(x: 6, y: 3))
            path.curve(to: NSPoint(x: 3, y: 6), controlPoint1: NSPoint(x: 4, y: 3), controlPoint2: NSPoint(x: 3, y: 4))
            path.line(to: NSPoint(x: 3, y: 15))
            path.curve(to: NSPoint(x: 6, y: 18), controlPoint1: NSPoint(x: 3, y: 17), controlPoint2: NSPoint(x: 4, y: 18))
            path.line(to: NSPoint(x: 15, y: 18))
            path.curve(to: NSPoint(x: 18, y: 15), controlPoint1: NSPoint(x: 17, y: 18), controlPoint2: NSPoint(x: 18, y: 17))
            path.line(to: NSPoint(x: 18, y: 9))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14.5, y: 1.5, width: 5, height: 5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
