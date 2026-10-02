import Foundation

/// The drum rows shown in the step editor.
enum DrumLane: Int, CaseIterable, Identifiable {
    case kick, snare, hat, open, perc

    var id: Int { rawValue }
    var title: String { ["Kick", "Snare", "Hat", "Open hat", "Perc"][rawValue] }

    var path: WritableKeyPath<Pattern, [[Float]]> {
        switch self {
        case .kick: \.kick
        case .snare: \.snare
        case .hat: \.hat
        case .open: \.open
        case .perc: \.perc
        }
    }

    /// Velocity for a hit placed by hand.
    var velocity: Float { [1, 0.9, 0.45, 0.4, 0.45][rawValue] }
}

extension Pattern {
    mutating func toggle(_ lane: DrumLane, bar: Int, step: Int) {
        let on = self[keyPath: lane.path][bar][step] > 0
        self[keyPath: lane.path][bar][step] = on ? 0 : lane.velocity
    }

    /// Places `midi` on the bass line at `step`, or removes it if it's already there.
    /// The line is monophonic: one note per step.
    mutating func toggleBass(bar: Int, step: Int, midi: Int) {
        if line[bar][step]?.midi == midi {
            line[bar][step] = nil
        } else {
            line[bar][step] = Hit(len: 1, vel: 0.8, midi: midi)
        }
        retimeLine(bar: bar)
    }

    /// Each note rings until the next one (at most a beat), so a hand-written line
    /// plays legato without the editor needing note lengths.
    mutating func retimeLine(bar: Int) {
        let starts = (0..<16).filter { line[bar][$0] != nil }
        for (i, s) in starts.enumerated() {
            let next = i + 1 < starts.count ? starts[i + 1] : 16
            line[bar][s]?.len = min(next - s, 4)
        }
    }

    /// Bottom note of the bass editor's octave: the key's root around E2–D♯3.
    var bassEditorBase: Int {
        var b = keyRoot % 12 + 36
        while b < 40 { b += 12 }
        return b
    }
}
