import Foundation

/// Drum patterns. Four come from the styles' own writers; breakbeat is extra.
enum DrumGroove: Int, CaseIterable, Identifiable, Codable {
    case boomBap, hardFour, softFour, halfTime, breakbeat, drift, jungle

    var id: Int { rawValue }

    var title: String {
        ["Boom-bap", "Hard 4/4", "Soft 4/4", "Half-time", "Breakbeat", "Drift", "Jungle"][rawValue]
    }

    /// The style whose pattern writer produces this groove (nil = breakbeat).
    var writer: Style? { [.tripHop, .industrial, .dreamy, .synth, nil, .ambient, .dnb][rawValue] }

    init(_ style: Style) { self = [.boomBap, .hardFour, .softFour, .halfTime, .drift, .jungle][style.rawValue] }
}

/// What every part of the band plays and sounds like. A preset is a recipe where all
/// parts follow one style; manual mode and the prompt mix and match them.
struct Recipe: Equatable, Codable {
    /// Chord progression flavour.
    var harmony: Style
    /// Key, as a pitch class (0 = C).
    var key: Int
    var drums: DrumGroove?            // nil = no drums
    var kit: Style
    var sub = true
    var bassSound: Style?             // nil = no bass line
    var bassPattern: Style
    var keys: Style?                  // nil = no keys
    var texture: Style?               // nil = no texture
    /// Bar (0-based) each track comes in on: drums, sub, bass, keys, texture.
    var enter = [0, 0, 0, 0, 0]

    static func preset(_ s: Style) -> Recipe {
        Recipe(harmony: s, key: s.keyRoot % 12, drums: DrumGroove(s), kit: s,
               bassSound: s, bassPattern: s, keys: s, texture: s)
    }

    var keyName: String { noteNames[key] + " minor" }

    /// The style that sets reverb, delay and overall balance.
    var main: Style { harmony }
}

let noteNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

// MARK: - Names shown in manual mode, per part

extension Style {
    var harmonyTitle: String { ["Dark minor", "Menace", "Dreamy", "Cold", "Desolate", "Liquid"][rawValue] }
    var kitTitle: String { ["Dusty", "Industrial", "Soft", "Glitch", "Metal", "Amen"][rawValue] }
    var bassSoundTitle: String { ["Driven", "Grind", "Pluck", "Pulse", "Drone", "Reese"][rawValue] }
    var bassPatternTitle: String { ["Riff", "Rolling", "Arpeggio", "Sixteenths", "Held", "Two-step"][rawValue] }
    var keysTitle: String { ["Rhodes", "Dark pad", "Warm pad", "Felt piano", "Eerie pad", "Strings"][rawValue] }
    var textureTitle: String { ["Vinyl haze", "Drone", "Tape", "Static", "Wind", "Rain"][rawValue] }
}
