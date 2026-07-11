import Foundation

/// Lightweight guest-facing localization (English / German) that needs
/// no String Catalog or bundle resources — picks the device's preferred language
/// at runtime. Used for the strings event guests actually see (attract screen,
/// camera prompts, delivery), so the booth reads natively at international
/// events. Operator/admin UI stays English.
///
/// Product decision (2026-07-07): the Polish market is NOT targeted — Polish
/// resolution is disabled; pl-locale devices get English (post-audit cleanup
/// removed the dead `pl:` translations from every call site).
enum Loc {
    /// Two-letter code of the device's top preferred language ("en"/"de"/…).
    static var lang: String {
        let id = Locale.preferredLanguages.first ?? "en"
        return String(id.prefix(2)).lowercased()
    }

    /// Return the string for the current language, falling back to English.
    static func t(_ en: String, de: String) -> String {
        switch lang {
        case "de": return de
        default:   return en
        }
    }
}
