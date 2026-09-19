import Foundation
import Speech

public enum SpeechLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en_US", polish = "pl_PL", spanish = "es_ES", german = "de_DE"
    public var id: String { rawValue }
    public var code: String { String(rawValue.prefix(2)) }
    public var name: String {
        switch self {
        case .english: "English"
        case .polish: "Polski"
        case .spanish: "Español"
        case .german: "Deutsch"
        }
    }
    public static var systemDefault: Self {
        for language in Locale.preferredLanguages {
            if let match = allCases.first(where: { language.hasPrefix($0.code) }) { return match }
        }
        return .english
    }
}

public enum SpeechEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, whisperSmall, whisperTurbo
    public var id: String { rawValue }
    public var modelName: String? {
        switch self {
        case .apple: nil
        case .whisperSmall: "ggml-small.bin"
        case .whisperTurbo: "ggml-large-v3-turbo.bin"
        }
    }
}

public struct SpeechSettings: Codable, Equatable, Sendable {
    public var language: SpeechLanguage
    public var engine: SpeechEngine
    public init(language: SpeechLanguage = .systemDefault, engine: SpeechEngine = .apple) {
        self.language = language
        self.engine = engine
    }
}

public enum SpeechReadiness: String, Sendable {
    case ready, permissionRequired, permissionDenied, appleModelMissing, whisperModelMissing, whisperRuntimeMissing
    public static func check(_ settings: SpeechSettings) -> Self {
        if settings.engine != .apple {
            guard LocalWhisperTranscriber.executableURL != nil else { return .whisperRuntimeMissing }
            return FileManager.default.isReadableFile(atPath: LocalWhisperTranscriber.modelURL(settings.engine).path)
                ? .ready : .whisperModelMissing
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return .permissionDenied
        default: break
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings.language.rawValue)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return .appleModelMissing }
        return SFSpeechRecognizer.authorizationStatus() == .notDetermined ? .permissionRequired : .ready
    }
}
