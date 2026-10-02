import Foundation

// MARK: - Style

enum Style: Int, CaseIterable, Identifiable, Codable {
    case tripHop, industrial, dreamy, synth, ambient

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tripHop: "Trip-Hop"
        case .industrial: "Industrial"
        case .dreamy: "Dreamy"
        case .synth: "Synth"
        case .ambient: "Ambient"
        }
    }

    /// MIDI note the progressions are built on.
    var keyRoot: Int { [50, 52, 57, 48, 47][rawValue] }  // D3, E3, A3, C3, B2
    var keyName: String { ["D minor", "E minor", "A minor", "C minor", "B minor"][rawValue] }

    struct Defaults { let bpm, swing, tone, grit, space: Double }

    var defaults: Defaults {
        switch self {
        case .tripHop: Defaults(bpm: 80, swing: 0.2, tone: 0.42, grit: 0.3, space: 0.55)
        case .industrial: Defaults(bpm: 116, swing: 0.0, tone: 0.7, grit: 0.55, space: 0.35)
        case .dreamy: Defaults(bpm: 104, swing: 0.12, tone: 0.55, grit: 0.12, space: 0.65)
        case .synth: Defaults(bpm: 96, swing: 0, tone: 0.5, grit: 0.35, space: 0.5)
        case .ambient: Defaults(bpm: 64, swing: 0, tone: 0.45, grit: 0.15, space: 0.85)
        }
    }

    var trackNames: [String] {
        switch self {
        case .tripHop: ["Drums", "Sub", "Bass", "Rhodes", "Haze"]
        case .industrial: ["Machine", "Sub", "Grind", "Pad", "Drone"]
        case .dreamy: ["Drums", "Sub", "Arp", "Pad", "Tape"]
        case .synth: ["Drums", "Drone", "Pulse", "Piano", "Static"]
        case .ambient: ["Metal", "Drone", "Low", "Pad", "Wind"]
        }
    }
}

// MARK: - Chords

enum Quality: Codable {
    case m7, m9, m11, maj7, maj9, dom9, dom13, dom7b9, five, flat2, tritone

    var intervals: [Int] {
        switch self {
        case .m7: [0, 3, 7, 10]
        case .m9: [0, 3, 7, 10, 14]
        case .m11: [0, 3, 10, 14, 17]
        case .maj7: [0, 4, 7, 11]
        case .maj9: [0, 4, 11, 14]
        case .dom9: [0, 4, 10, 14]
        case .dom13: [0, 10, 16, 21]
        case .dom7b9: [0, 4, 10, 13]
        case .five: [0, 7, 12]
        case .flat2: [0, 1, 7, 12]
        case .tritone: [0, 6, 12]
        }
    }

    var suffix: String {
        switch self {
        case .m7: "m7"
        case .m9: "m9"
        case .m11: "m11"
        case .maj7: "maj7"
        case .maj9: "maj9"
        case .dom9: "9"
        case .dom13: "13"
        case .dom7b9: "7♭9"
        case .five: "5"
        case .flat2: "5♭9"
        case .tritone: "♭5"
        }
    }
}


private func progressions(_ style: Style) -> [[(Int, Quality)]] {
    switch style {
    // Mezzanine-dark: minor chords, a phrygian ♭II and a menacing ♭9 dominant.
    case .tripHop: [
        [(0, .m7), (0, .m7), (1, .maj7), (0, .m7)],
        [(0, .m9), (8, .maj7), (5, .m7), (7, .dom7b9)],
        [(0, .m7), (0, .m7), (8, .maj7), (7, .five)],
        [(0, .m11), (5, .m7), (1, .maj7), (0, .m7)],
    ]
    case .industrial: [
        [(0, .five), (0, .five), (1, .flat2), (10, .tritone)],
        [(0, .five), (3, .five), (1, .flat2), (0, .tritone)],
        [(0, .flat2), (0, .five), (5, .tritone), (1, .five)],
    ]
    // Desolate: bare fifths and minor chords that drift a half-step and back.
    case .ambient: [
        [(0, .m7), (0, .m7), (1, .five), (0, .five)],
        [(0, .five), (8, .five), (0, .five), (1, .five)],
        [(0, .m9), (0, .m9), (10, .five), (1, .five)],
    ]
    // Minimal and bruised: C minor sitting on A♭ and E♭, open fifths on B♭.
    case .synth: [
        [(0, .m7), (0, .m7), (8, .maj7), (8, .maj7)],
        [(0, .five), (8, .maj7), (3, .maj7), (10, .five)],
        [(0, .m7), (5, .m7), (8, .maj7), (7, .five)],
    ]
    case .dreamy: [
        [(0, .m9), (8, .maj9), (3, .maj7), (10, .dom9)],
        [(0, .m9), (5, .m9), (8, .maj9), (7, .m7)],
        [(8, .maj9), (3, .maj7), (10, .dom9), (0, .m11)],
    ]
    }
}

// MARK: - RNG

struct RNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func float() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func chance(_ p: Float) -> Bool { float() < p }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}

// MARK: - Pattern

struct Hit: Codable, Equatable {
    var len: Int        // in 16th steps
    var vel: Float
    var midi = 0
}

/// Four bars of 16 steps. Drum lanes hold velocities (0 = silent). `bass` is the sub,
/// `line` the audible bass part, `comp` the rhythm of the keys' chords, `melody` single
/// notes on the keys sound.
struct Pattern: Codable, Equatable {
    /// The main style: harmony, reverb and overall balance.
    let style: Style
    /// Which style's sound each part uses (they can differ in manual mode).
    var kit: Style, bassSound: Style, keysSound: Style, textureSound: Style
    var hasTexture = true
    /// Bar each track enters on (drums, sub, bass, keys, texture); later bars loop all in.
    var enter = [0, 0, 0, 0, 0]
    var keyName = ""
    /// MIDI note of the key's root, for re-voicing chords edited by hand.
    var keyRoot = 48
    var kick = Pattern.lane(), snare = Pattern.lane(), hat = Pattern.lane()
    var open = Pattern.lane(), perc = Pattern.lane()
    var bass = Pattern.notes(), line = Pattern.notes(), comp = Pattern.notes(), melody = Pattern.notes()
    var chords: [[Int]] = []
    var bassRoots: [Int] = []
    var chordNames: [String] = []

    static func lane() -> [[Float]] { Array(repeating: Array(repeating: 0, count: 16), count: 4) }
    static func notes() -> [[Hit?]] { Array(repeating: Array(repeating: nil, count: 16), count: 4) }

    /// A chord `root` semitones above the key, voiced inside the on-screen keyboard
    /// (C3–E5), with its bass root and name.
    static func voice(keyRoot: Int, root: Int, _ q: Quality) -> (chord: [Int], bassRoot: Int, name: String) {
        var base = keyRoot + root
        while base > 59 { base -= 12 }
        while base < 48 { base += 12 }
        var b = keyRoot + root - 24
        while b < 31 { b += 12 }
        while b > 42 { b -= 12 }
        return (q.intervals.map { base + $0 }, b, noteNames[((keyRoot + root) % 12 + 12) % 12] + q.suffix)
    }

    /// Chords offered when swapping one by hand: the key's own, plus the dark ♭II.
    static let chordChoices: [(root: Int, quality: Quality)] = [
        (0, .m7), (0, .m9), (0, .m11), (0, .five), (1, .maj7), (3, .maj7), (5, .m7), (5, .m9),
        (7, .m7), (7, .dom7b9), (7, .five), (8, .maj7), (8, .maj9), (10, .dom9), (10, .five),
    ]

    /// Replaces bar `bar`'s chord, moving that bar's bass, sub and melody notes by the
    /// same amount so they follow the new root.
    mutating func setChord(bar: Int, root: Int, _ q: Quality) {
        let v = Pattern.voice(keyRoot: keyRoot, root: root, q)
        var shift = (v.bassRoot - bassRoots[bar]) % 12
        if shift > 6 { shift -= 12 } else if shift < -6 { shift += 12 }
        chords[bar] = v.chord
        chordNames[bar] = v.name
        bassRoots[bar] = v.bassRoot
        for s in 0..<16 {
            bass[bar][s]?.midi += shift
            line[bar][s]?.midi += shift
            melody[bar][s]?.midi += shift
        }
    }

    static func make(_ style: Style, seed: UInt64) -> Pattern {
        make(.preset(style), seed: seed)
    }

    /// Builds each part with its own style's writer over one shared progression. Each
    /// part draws from its own random stream, so changing one part leaves the rest as is.
    static func make(_ recipe: Recipe, seed: UInt64) -> Pattern {
        var r = RNG(seed: seed)
        var p = Pattern(style: recipe.harmony,
                        kit: recipe.kit, bassSound: recipe.bassSound ?? recipe.harmony,
                        keysSound: recipe.keys ?? recipe.harmony,
                        textureSound: recipe.texture ?? recipe.harmony)
        p.hasTexture = recipe.texture != nil
        p.enter = recipe.enter
        p.keyName = recipe.keyName

        // Keep the key's root near the style's own register.
        var keyRoot = recipe.harmony.keyRoot - recipe.harmony.keyRoot % 12 + recipe.key
        if keyRoot - recipe.harmony.keyRoot > 6 { keyRoot -= 12 }
        p.keyRoot = keyRoot
        for (root, q) in r.pick(progressions(recipe.harmony)) {
            let v = voice(keyRoot: keyRoot, root: root, q)
            p.chords.append(v.chord)
            p.bassRoots.append(v.bassRoot)
            p.chordNames.append(v.name)
        }

        func written(_ style: Style?, stream: UInt64) -> Pattern {
            var scratch = p
            var rr = RNG(seed: seed ^ (stream &* 0x9E37_79B9_7F4A_7C15))
            switch style {
            case .tripHop: scratch.writeTripHop(&rr)
            case .industrial: scratch.writeIndustrial(&rr)
            case .dreamy: scratch.writeDreamy(&rr)
            case .synth: scratch.writeSynth(&rr)
            case .ambient: scratch.writeAmbient(&rr)
            case nil: scratch.writeBreakbeat(&rr)
            }
            return scratch
        }

        if let groove = recipe.drums {
            let d = written(groove.writer, stream: 1)
            (p.kick, p.snare, p.hat, p.open, p.perc) = (d.kick, d.snare, d.hat, d.open, d.perc)
        }
        let b = written(recipe.bassPattern, stream: 2)
        if recipe.sub { p.bass = b.bass }
        if recipe.bassSound != nil { p.line = b.line }
        if let keys = recipe.keys {
            let k = written(keys, stream: 3)
            (p.comp, p.melody) = (k.comp, k.melody)
        }
        return p
    }

    /// Dark, heavy trip-hop in the Mezzanine vein: slow, sparse drums with a big snare,
    /// a heartbeat kick option, a sustained sub and a brooding, driven bass riff.
    private mutating func writeTripHop(_ r: inout RNG) {
        let kicks = r.pick([[0, 10], [0, 2, 10], [0, 7, 10], [0, 3, 10], [0, 1, 8, 9]])   // [0,1,…] = heartbeat
        let ghost = r.pick([7, 9, 15])
        let openOn14 = r.chance(0.35)
        let rim = r.chance(0.35) ? r.pick([7, 13]) : -1

        // A short, repeating riff around the root: octave, minor third and the ♭2 that
        // gives the menace. Long notes, mostly on the beat.
        let riffs: [[(step: Int, len: Int, iv: Int)]] = [
            [(0, 3, 0), (3, 3, 0), (6, 2, 12), (10, 4, 0)],
            [(0, 6, 0), (8, 2, 3), (10, 4, 1)],
            [(0, 3, 0), (3, 3, 0), (8, 4, -2), (12, 3, 0)],
            [(0, 4, 0), (6, 2, 12), (8, 6, 1)],
        ]
        let riff = r.pick(riffs)

        for bar in 0..<4 {
            for s in kicks { kick[bar][s] = s == 0 || s == 8 ? 1 : 0.75 }
            snare[bar][4] = 1
            snare[bar][12] = 1
            if r.chance(0.4) { snare[bar][ghost] = 0.18 }
            for s in stride(from: 0, to: 16, by: 2) { hat[bar][s] = s % 4 == 0 ? 0.45 : 0.3 }
            if openOn14 { hat[bar][14] = 0; open[bar][14] = 0.3 }
            if rim >= 0 { perc[bar][rim] = 0.3 }

            let root = bassRoots[bar]
            bass[bar][0] = Hit(len: 8, vel: 1, midi: root)
            bass[bar][8] = Hit(len: 7, vel: 0.85, midi: root)
            for n in riff {
                line[bar][n.step] = Hit(len: n.len, vel: n.step == 0 ? 0.9 : 0.75, midi: root + 12 + n.iv)
            }

            comp[bar][0] = Hit(len: 15, vel: 0.6)
            if r.chance(0.25) { comp[bar][11] = Hit(len: 4, vel: 0.35) }
        }
        if r.chance(0.6) { snare[3][14] = 0.4; snare[3][15] = 0.25 }
    }

    private mutating func writeIndustrial(_ r: inout RNG) {
        let extraKick = r.pick([-1, 7, 14, 15, 3])
        let percSteps = [r.pick([3, 5, 11]), r.pick([7, 9, 13, 15])]
        let octaveJumps = r.chance(0.5)

        for bar in 0..<4 {
            for s in [0, 4, 8, 12] { kick[bar][s] = 1 }
            if extraKick >= 0 { kick[bar][extraKick] = 0.6 }
            snare[bar][4] = 1
            snare[bar][12] = 1
            for s in 0..<16 {
                if s % 4 == 2 { open[bar][s] = 0.45 } else { hat[bar][s] = s % 2 == 1 ? 0.35 : 0.22 }
            }
            for s in percSteps { perc[bar][s] = 0.6 }

            // Sub holds the root; the rolling 16th line ducks out of the kick.
            let root = bassRoots[bar]
            bass[bar][0] = Hit(len: 15, vel: 0.7, midi: root)
            for s in 0..<16 where s % 4 != 0 {
                line[bar][s] = Hit(len: 1, vel: s % 4 == 2 ? 1 : 0.75,
                                   midi: octaveJumps && s % 8 == 7 ? root + 12 : root)
            }
            comp[bar][0] = Hit(len: 16, vel: 0.5)
        }
        for (i, s) in [13, 14, 15].enumerated() { snare[3][s] = 0.5 + 0.2 * Float(i) }
    }

    /// Ambient techno in the Board of Canada / Moby vein: a soft four-to-the-floor, a held
    /// sub, a slow pad per bar and a plucked arpeggio running through the chord.
    private mutating func writeDreamy(_ r: inout RNG) {
        let shape = r.pick([[0, 1, 2, 3, 2, 1, 0, 1], [0, 2, 1, 3, 0, 2, 1, 3],
                            [0, 1, 2, 3, 4, 3, 2, 1], [3, 2, 1, 0, 1, 2, 3, 2]])
        let rests = (0..<8).map { i in i > 0 && r.chance(0.2) }
        let rim = r.pick([7, 11, 15])
        let openOn14 = r.chance(0.5)

        for bar in 0..<4 {
            for s in [0, 4, 8, 12] { kick[bar][s] = 0.8 }
            snare[bar][4] = 0.55
            snare[bar][12] = 0.55
            for s in [2, 6, 10, 14] { hat[bar][s] = 0.3 }
            for s in stride(from: 1, to: 16, by: 2) { if r.chance(0.3) { hat[bar][s] = 0.12 } }
            if openOn14 { hat[bar][14] = 0; open[bar][14] = 0.25 }
            if r.chance(0.6) { perc[bar][rim] = 0.3 }

            let root = bassRoots[bar]
            bass[bar][0] = Hit(len: 8, vel: 0.8, midi: root)
            bass[bar][8] = Hit(len: 7, vel: 0.7, midi: root)

            let notes = chords[bar].sorted()
            for (i, idx) in shape.enumerated() where !rests[i] {
                line[bar][i * 2] = Hit(len: 2, vel: i % 4 == 0 ? 0.8 : 0.6, midi: notes[idx % notes.count] + 12)
            }
            comp[bar][0] = Hit(len: 16, vel: 0.55)
        }
    }

    /// Score-like and restrained, after the Social Network soundtrack: a sparse felt-piano
    /// melody over soft chords, a long saturated drone, a driving 16th-note analog pulse
    /// and minimal, glitchy percussion.
    private mutating func writeSynth(_ r: inout RNG) {
        let pulse = r.pick([[0, 0, 12, 0, 7, 0, 12, 0, 0, 0, 12, 0, 7, 0, 10, 0],
                            [0, 12, 0, 7, 0, 12, 0, 7, 0, 12, 0, 7, 0, 12, 3, 7],
                            [0, 7, 12, 7, 0, 7, 12, 7, 0, 7, 12, 15, 12, 7, 0, 7]])
        let tickGaps = (0..<16).map { _ in r.chance(0.3) }
        let melodySteps = r.pick([[0, 6, 10], [3, 8, 14], [0, 4, 11], [2, 8]])
        let melodyPick = melodySteps.map { _ in Int(r.next() % 4) }

        for bar in 0..<4 {
            kick[bar][0] = 0.7
            if bar % 2 == 1 || r.chance(0.3) { kick[bar][8] = 0.55 }
            if bar % 2 == 1 { snare[bar][12] = 0.5 }
            for s in 0..<16 where !tickGaps[s] { hat[bar][s] = s % 4 == 0 ? 0.25 : 0.12 }
            if r.chance(0.5) { perc[bar][r.pick([5, 7, 13, 15])] = 0.5 }

            let root = bassRoots[bar]
            bass[bar][0] = Hit(len: 16, vel: 0.8, midi: root)
            for s in 0..<16 {
                line[bar][s] = Hit(len: 1, vel: s % 4 == 0 ? 0.85 : 0.6, midi: root + 12 + pulse[s])
            }
            comp[bar][0] = Hit(len: 16, vel: 0.35)
            let notes = chords[bar].sorted()
            for (i, s) in melodySteps.enumerated() {
                melody[bar][s] = Hit(len: 6, vel: 0.65, midi: notes[melodyPick[i] % notes.count] + 12)
            }
        }
    }

    /// A classic breakbeat (Prodigy / Chemical Brothers): syncopated kicks, a snare with
    /// ghost notes and a late hit, busy hats. Drums only; other lanes are left alone.
    private mutating func writeBreakbeat(_ r: inout RNG) {
        let kicks = r.pick([[0, 2, 10], [0, 10, 11], [0, 3, 8, 10], [0, 2, 7, 10]])
        let late = r.chance(0.5)
        for bar in 0..<4 {
            for s in kicks { kick[bar][s] = s == 0 ? 1 : 0.85 }
            snare[bar][4] = 1
            snare[bar][12] = 1
            for s in [7, 9] { if r.chance(0.6) { snare[bar][s] = 0.3 } }
            if late { snare[bar][15] = 0.55 }
            for s in 0..<16 { hat[bar][s] = s % 2 == 0 ? 0.5 : (r.chance(0.6) ? 0.25 : 0) }
            if r.chance(0.5) { hat[bar][6] = 0; open[bar][6] = 0.4 }
            if r.chance(0.4) { perc[bar][r.pick([3, 11, 14])] = 0.45 }
        }
        snare[3][13] = 0.6
        snare[3][14] = 0.8
    }

    /// Dark ambient in the S.T.A.L.K.E.R. / MoozE vein: no beat, just distant thuds,
    /// creaks and metal clangs, a held drone and a wavering low line that slips down a
    /// half-step, a slow eerie pad and the odd lonely note.
    private mutating func writeAmbient(_ r: inout RNG) {
        let clangs = (0..<4).map { _ in r.chance(0.6) ? r.pick([3, 6, 9, 13]) : -1 }
        for bar in 0..<4 {
            if bar % 2 == 0 || r.chance(0.3) { kick[bar][0] = 0.5 }                  // far-off thud
            if clangs[bar] >= 0 { perc[bar][clangs[bar]] = 0.4 + 0.3 * r.float() }   // metal
            if bar == 2 || r.chance(0.25) { snare[bar][r.pick([4, 8, 10])] = 0.5 }   // creak
            for s in 0..<16 { if r.chance(0.08) { hat[bar][s] = 0.15 + 0.2 * r.float() } }

            let root = bassRoots[bar]
            bass[bar][0] = Hit(len: 16, vel: 0.75, midi: root)
            line[bar][0] = Hit(len: 16, vel: 0.6, midi: root + 12 + (bar == 3 ? 1 : 0))
            comp[bar][0] = Hit(len: 16, vel: 0.3)
            if r.chance(0.6) {
                let notes = chords[bar].sorted()
                melody[bar][r.pick([2, 6, 9, 12])] = Hit(len: 8, vel: 0.4, midi: notes[Int(r.next() % UInt64(notes.count))] + 12)
            }
        }
    }
}
