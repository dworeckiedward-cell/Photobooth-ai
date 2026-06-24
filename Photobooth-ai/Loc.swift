import Foundation

/// Lightweight guest-facing localization (English / Polish / German) that needs
/// no String Catalog or bundle resources — picks the device's preferred language
/// at runtime. Used for the strings event guests actually see (attract screen,
/// Instant Looks, camera prompts), so the booth reads natively at international
/// events. Operator/admin UI stays English.
enum Loc {
    /// Two-letter code of the device's top preferred language ("en"/"pl"/"de"/…).
    static var lang: String {
        let id = Locale.preferredLanguages.first ?? "en"
        return String(id.prefix(2)).lowercased()
    }

    /// Return the string for the current language, falling back to English.
    static func t(_ en: String, pl: String, de: String) -> String {
        switch lang {
        case "pl": return pl
        case "de": return de
        default:   return en
        }
    }
}
