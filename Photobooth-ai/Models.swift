import Foundation
import SwiftUI

// MARK: - Styles
//
// Domain types around `PhotoStyle`. The enum itself is the wire type (raw values
// must match the Supabase `photo_style` enum exactly — keep in sync with
// `webapp src/lib/constants.ts STYLE_META`).

enum PhotoStyle: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    // Batch 1 — original styles
    case astronauta
    case superbohater
    case cyberpunk
    case motocyklista
    case rycerz
    case pirat
    case wiking
    case dziki_zachod
    case budowlaniec
    case rolnik
    // Batch 2 — new styles (DB migration 00000000000013)
    case rockstar
    case samurai
    case detective
    case szef_kuchni
    case wojskowy
    case tajny_agent
    case egipcjanin
    case ninja
    case steampunk
    case czarownik
    case pilotka
    case kosmita

    var id: String { rawValue }

    var label: String {
        switch self {
        case .astronauta:    "Astronaut"
        case .superbohater:  "Superhero"
        case .cyberpunk:     "Cyberpunk"
        case .motocyklista:  "Biker"
        case .rycerz:        "Knight"
        case .pirat:         "Pirate"
        case .wiking:        "Viking"
        case .dziki_zachod:  "Wild West"
        case .budowlaniec:   "Construction"
        case .rolnik:        "Farmer"
        case .rockstar:      "Rock Star"
        case .samurai:       "Samurai"
        case .detective:     "Detective"
        case .szef_kuchni:   "Chef"
        case .wojskowy:      "Soldier"
        case .tajny_agent:   "Secret Agent"
        case .egipcjanin:    "Egyptian Royal"
        case .ninja:         "Ninja"
        case .steampunk:     "Steampunk"
        case .czarownik:     "Wizard"
        case .pilotka:       "Fighter Pilot"
        case .kosmita:       "Alien Visitor"
        }
    }

    var descriptionText: String {
        switch self {
        case .astronauta:    "Outer space, NASA, Earth"
        case .superbohater:  "Cape, Gotham, raw power"
        case .cyberpunk:     "Neon, Tokyo 2099, holograms"
        case .motocyklista:  "Highway, Harley, leather"
        case .rycerz:        "Armor, sword, castle"
        case .pirat:         "Ship, ocean, treasure"
        case .wiking:        "Axe, furs, fjords"
        case .dziki_zachod:  "Hat, horse, open prairie"
        case .budowlaniec:   "Job site, hard hat, hi-vis vest"
        case .rolnik:        "Fields, tractor, hay bales"
        case .rockstar:      "Stage, guitar, screaming crowd"
        case .samurai:       "Cherry blossoms, katana, honor"
        case .detective:     "Noir, trench coat, rain"
        case .szef_kuchni:   "Michelin kitchen, toque, fire"
        case .wojskowy:      "Combat gear, mission, valor"
        case .tajny_agent:   "Tuxedo, casino, shaken not stirred"
        case .egipcjanin:    "Pharaoh, gold, pyramids at dusk"
        case .ninja:         "Shadow, moonlit rooftop, katana"
        case .steampunk:     "Brass goggles, airship, Victorian"
        case .czarownik:     "Spells, ancient library, glowing runes"
        case .pilotka:       "Flight suit, jet, Top Gun vibes"
        case .kosmita:       "Bioluminescent planet, alien world"
        }
    }

    var iconSymbol: String {
        switch self {
        case .astronauta:    "moon.stars.fill"
        case .superbohater:  "bolt.shield.fill"
        case .cyberpunk:     "waveform.path.ecg"
        case .motocyklista:  "bicycle"
        case .rycerz:        "shield.lefthalf.filled"
        case .pirat:         "sailboat.fill"
        case .wiking:        "hammer.fill"
        case .dziki_zachod:  "sun.max.fill"
        case .budowlaniec:   "hammer.circle.fill"
        case .rolnik:        "leaf.fill"
        case .rockstar:      "music.mic"
        case .samurai:       "sword"
        case .detective:     "magnifyingglass.circle.fill"
        case .szef_kuchni:   "fork.knife"
        case .wojskowy:      "star.circle.fill"
        case .tajny_agent:   "eyeglasses"
        case .egipcjanin:    "pyramid"
        case .ninja:         "figure.martial.arts"
        case .steampunk:     "gearshape.fill"
        case .czarownik:     "sparkles"
        case .pilotka:       "airplane"
        case .kosmita:       "globe.americas.fill"
        }
    }

    /// Asset catalog name for the AI-styled sample photo.
    /// Returns nil when the asset hasn't been added yet — StyleTile shows
    /// an icon+gradient placeholder instead of a broken image.
    var previewAsset: String? {
        let name = "Style_\(rawValue)"
        // Check if the image exists in the asset catalog at runtime.
        // UIImage(named:) returns nil for missing assets.
        return UIImage(named: name) != nil ? name : nil
    }

    var accentGradient: LinearGradient {
        let colors: [Color] = switch self {
        case .astronauta:
            [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.36, green: 0.18, blue: 0.55)]
        case .superbohater:
            [Color(red: 0.86, green: 0.20, blue: 0.27), Color(red: 0.18, green: 0.27, blue: 0.65)]
        case .cyberpunk:
            [Color(red: 0.93, green: 0.30, blue: 0.60), Color(red: 0.13, green: 0.59, blue: 0.71)]
        case .motocyklista:
            [Color(red: 0.27, green: 0.26, blue: 0.29), Color(red: 0.09, green: 0.09, blue: 0.10)]
        case .rycerz:
            [Color(red: 0.46, green: 0.46, blue: 0.50), Color(red: 0.18, green: 0.20, blue: 0.24)]
        case .pirat:
            [Color(red: 0.65, green: 0.36, blue: 0.10), Color(red: 0.60, green: 0.05, blue: 0.12)]
        case .wiking:
            [Color(red: 0.42, green: 0.39, blue: 0.34), Color(red: 0.10, green: 0.13, blue: 0.16)]
        case .dziki_zachod:
            [Color(red: 0.78, green: 0.55, blue: 0.10), Color(red: 0.55, green: 0.30, blue: 0.05)]
        case .budowlaniec:
            [Color(red: 0.96, green: 0.55, blue: 0.10), Color(red: 0.72, green: 0.36, blue: 0.05)]
        case .rolnik:
            [Color(red: 0.13, green: 0.77, blue: 0.40), Color(red: 0.06, green: 0.40, blue: 0.16)]
        case .rockstar:
            [Color(red: 0.85, green: 0.10, blue: 0.40), Color(red: 0.40, green: 0.05, blue: 0.60)]
        case .samurai:
            [Color(red: 0.70, green: 0.10, blue: 0.10), Color(red: 0.15, green: 0.10, blue: 0.20)]
        case .detective:
            [Color(red: 0.25, green: 0.25, blue: 0.30), Color(red: 0.08, green: 0.08, blue: 0.12)]
        case .szef_kuchni:
            [Color(red: 0.95, green: 0.75, blue: 0.10), Color(red: 0.70, green: 0.20, blue: 0.05)]
        case .wojskowy:
            [Color(red: 0.25, green: 0.38, blue: 0.15), Color(red: 0.10, green: 0.18, blue: 0.08)]
        case .tajny_agent:
            [Color(red: 0.10, green: 0.10, blue: 0.25), Color(red: 0.05, green: 0.05, blue: 0.12)]
        case .egipcjanin:
            [Color(red: 0.85, green: 0.65, blue: 0.10), Color(red: 0.60, green: 0.30, blue: 0.05)]
        case .ninja:
            [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.05, green: 0.05, blue: 0.08)]
        case .steampunk:
            [Color(red: 0.65, green: 0.45, blue: 0.15), Color(red: 0.35, green: 0.20, blue: 0.05)]
        case .czarownik:
            [Color(red: 0.40, green: 0.15, blue: 0.75), Color(red: 0.10, green: 0.05, blue: 0.35)]
        case .pilotka:
            [Color(red: 0.10, green: 0.35, blue: 0.75), Color(red: 0.05, green: 0.15, blue: 0.45)]
        case .kosmita:
            [Color(red: 0.10, green: 0.70, blue: 0.60), Color(red: 0.05, green: 0.25, blue: 0.40)]
        }
        return LinearGradient(colors: colors.map { $0.opacity(0.65) }, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Photo status
//
// Mirrors the Supabase `photo_status` enum. Webapp:`/api/photos/[id]` returns this verbatim.

enum PhotoStatus: String, Codable, Hashable, Sendable {
    case pending
    case uploaded
    case generating
    case completed
    case failed

    var isTerminal: Bool { self == .completed || self == .failed }
}
