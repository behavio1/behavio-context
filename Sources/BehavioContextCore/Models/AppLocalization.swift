import Foundation

public enum AppLocalization {
    public static func text(_ key: String, locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        let chosen = ["pl", "en", "es", "de"].contains(code) ? code : "en"
        guard let path = Bundle.main.path(forResource: chosen, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
