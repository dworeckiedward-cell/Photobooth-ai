import Foundation
import SwiftUI

// MARK: - Styles
//
// Domain types around `PhotoStyle`. The enum itself is the wire type (raw values
// must match the Supabase `photo_style` enum exactly — keep in sync with
// `webapp src/lib/constants.ts STYLE_META`).

enum PhotoStyle: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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
        }
    }

    /// Asset catalog name for the real AI-styled sample photo.
    var previewAsset: String { "Style_\(rawValue)" }

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
