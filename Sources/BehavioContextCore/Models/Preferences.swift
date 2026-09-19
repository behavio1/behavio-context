import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case polish = "pl"
    case spanish = "es"
    case german = "de"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .system
    }

    public func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        for preference in preferredLanguages {
            let code = Locale(identifier: preference).language.languageCode?.identifier ?? ""
            if ["pl", "en", "es", "de"].contains(code) { return code }
        }
        return "en"
    }

    public var id: String { rawValue }
    public var localeIdentifier: String? { self == .system ? nil : rawValue }

}

public struct PreferencesSnapshot: Codable, Equatable, Sendable {
    public var selectedCaptureSourceID: CaptureSourceID?
    public var lastCaptureSourceKind: CaptureSourceKind?
    public var capturesMicrophone: Bool
    public var microphoneDeviceID: String?
    public var language: AppLanguage
    public var speech: SpeechSettings
    public var globalShortcut: GlobalShortcut

    public init(
        selectedCaptureSourceID: CaptureSourceID? = nil,
        lastCaptureSourceKind: CaptureSourceKind? = nil,
        capturesMicrophone: Bool = true,
        microphoneDeviceID: String? = nil,
        language: AppLanguage = .system,
        speech: SpeechSettings = SpeechSettings(),
        globalShortcut: GlobalShortcut = .defaultShortcut
    ) {
        self.selectedCaptureSourceID = selectedCaptureSourceID
        self.lastCaptureSourceKind = lastCaptureSourceKind
        self.capturesMicrophone = capturesMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.speech = speech
        self.language = language
        self.globalShortcut = globalShortcut
    }

    public static let defaults = PreferencesSnapshot()

    private enum CodingKeys: String, CodingKey {
        case selectedCaptureSourceID, lastCaptureSourceKind, capturesMicrophone
        case microphoneDeviceID, language, globalShortcut
        case speech
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedCaptureSourceID = try values.decodeIfPresent(CaptureSourceID.self, forKey: .selectedCaptureSourceID)
        lastCaptureSourceKind = try values.decodeIfPresent(CaptureSourceKind.self, forKey: .lastCaptureSourceKind)
        capturesMicrophone = try values.decodeIfPresent(Bool.self, forKey: .capturesMicrophone) ?? true
        microphoneDeviceID = try values.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        speech = (try? values.decode(SpeechSettings.self, forKey: .speech)) ?? SpeechSettings()
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        // Older preferences only stored an enable switch. Always restore an active shortcut.
        let shortcut = try? values.decode(GlobalShortcut.self, forKey: .globalShortcut)
        if let shortcut, shortcut.isValid {
            globalShortcut = shortcut
        } else {
            globalShortcut = .defaultShortcut
        }
    }

    public var sanitizedForPersistence: PreferencesSnapshot {
        var snapshot = self
        if !snapshot.globalShortcut.isValid {
            snapshot.globalShortcut = .defaultShortcut
        }
        if let selectedCaptureSourceID {
            snapshot.lastCaptureSourceKind = selectedCaptureSourceID.kind
        }
        if snapshot.lastCaptureSourceKind == .window {
            snapshot.selectedCaptureSourceID = nil
        }
        return snapshot
    }
}
