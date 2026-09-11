import Carbon
import Foundation
import BehavioContextCore
import OSLog

final class GlobalShortcutController: @unchecked Sendable {
    private static let signature = OSType(0x4243564F) // BCVO
    private static let recordingIdentifier: UInt32 = 1
    private static let escapeIdentifier: UInt32 = 2
    private var hotKey: EventHotKeyRef?
    private var escapeHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private let action: @Sendable () -> Void
    private let escapeAction: @Sendable () -> Void
    private let logger = Logger(subsystem: "one.behavio.context", category: "global-shortcut")

    init(
        action: @escaping @Sendable () -> Void,
        escapeAction: @escaping @Sendable () -> Void
    ) {
        self.action = action
        self.escapeAction = escapeAction
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let controller = Unmanaged<GlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == GlobalShortcutController.signature else { return noErr }
                switch identifier.id {
                case GlobalShortcutController.recordingIdentifier:
                    controller.logger.notice("Recording shortcut received")
                    controller.action()
                case GlobalShortcutController.escapeIdentifier:
                    controller.logger.notice("Escape shortcut received")
                    controller.escapeAction()
                default: break
                }
                return noErr
            },
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregister()
        setEscapeEnabled(false)
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        if registeredShortcut?.keyCode == shortcut.keyCode,
           registeredShortcut?.modifiers == shortcut.modifiers { return true }
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.recordingIdentifier
        )
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &replacement
        )
        guard status == noErr, let replacement else {
            logger.error("Recording shortcut registration failed with status \(status, privacy: .public)")
            return false
        }
        // Keep the previous shortcut working if the replacement is unavailable.
        unregister()
        hotKey = replacement
        registeredShortcut = shortcut
        logger.notice("Recording shortcut registered")
        return true
    }

    @discardableResult
    func setEscapeEnabled(_ enabled: Bool) -> Bool {
        if !enabled {
            if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
            escapeHotKey = nil
            return true
        }
        guard escapeHotKey == nil else { return true }
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.escapeIdentifier
        )
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            identifier,
            GetApplicationEventTarget(),
            0,
            &replacement
        )
        guard status == noErr, let replacement else {
            logger.error("Escape shortcut registration failed with status \(status, privacy: .public)")
            return false
        }
        escapeHotKey = replacement
        logger.notice("Escape shortcut registered")
        return true
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
            registeredShortcut = nil
        }
    }
}
