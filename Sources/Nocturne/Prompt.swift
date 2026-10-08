import Foundation
import FoundationModels

/// What the prompt interpreter fills in. Every choice maps onto one manual-mode control.
/// `plan` comes first so the model describes its idea before committing to settings.
@Generable
struct GrooveSpec {
    @Guide(description: "One or two sentences on the sound you are going for and which drums, bass, keys and texture you chose")
    var plan: String
    @Guide(description: "Tempo in BPM. 'Slow' or 'low tempo' means about 70 to 95", .range(60...180))
    var bpm: Int
    @Guide(description: "Key root note; the music is always minor", .anyOf(["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]))
    var key: String
    @Guide(description: "Chord flavour", .anyOf(["dark minor", "menace", "dreamy", "cold", "desolate", "liquid"]))
    var harmony: String
    @Guide(description: "Drum pattern", .anyOf(["boom-bap", "hard four-on-the-floor", "soft four-on-the-floor", "half-time", "breakbeat", "drift", "jungle", "none"]))
    var drums: String
    @Guide(description: "Drum kit sound", .anyOf(["dusty", "industrial", "soft", "glitch", "metal", "amen"]))
    var drumKit: String
    @Guide(description: "Whether a deep sub bass plays under everything")
    var sub: Bool
    @Guide(description: "Bass line sound", .anyOf(["driven", "grind", "pluck", "pulse", "drone", "reese", "none"]))
    var bassSound: String
    @Guide(description: "Bass line pattern", .anyOf(["riff", "rolling", "arpeggio", "sixteenths", "held", "two-step"]))
    var bassPattern: String
    @Guide(description: "Keys sound", .anyOf(["rhodes", "dark pad", "warm pad", "felt piano", "eerie pad", "strings", "none"]))
    var keys: String
    @Guide(description: "Background texture", .anyOf(["vinyl haze", "drone", "tape", "static", "wind", "rain", "none"]))
    var texture: String
    @Guide(description: "0 is bright and open, 10 is pitch dark", .range(0...10))
    var darkness: Int
    @Guide(description: "0 is clean, 10 is heavily distorted", .range(0...10))
    var distortion: Int
    @Guide(description: "Reverb and delay, 0 is dry, 10 is huge", .range(0...10))
    var space: Int
    @Guide(description: "Bar (1-8) the drums come in on", .range(1...8))
    var drumsEnter: Int
    @Guide(description: "Bar (1-8) the bass and sub come in on", .range(1...8))
    var bassEnter: Int
    @Guide(description: "Bar (1-8) the keys come in on", .range(1...8))
    var keysEnter: Int
    @Guide(description: "Bar (1-8) the texture comes in on", .range(1...8))
    var textureEnter: Int
}

/// Turns a musician's description into settings. On-device for now; a Claude-backed
/// interpreter can implement the same protocol later.
protocol PromptInterpreter {
    func interpret(_ prompt: String) async throws -> GrooveSpec
}

struct AppleInterpreter: PromptInterpreter {
    /// Nil when the on-device model can be used, otherwise why not.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use prompts."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again in a little while."
        case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
    }

    private static let instructions = """
    You set up a small groovebox that plays a looping, minor-key instrumental. Choose settings \
    that match the musician's description.

    Style hints:
    - The Prodigy, Chemical Brothers, big beat: breakbeat drums, industrial kit, grind bass, rolling pattern, \
    drone texture, distortion 5 or more.
    - Massive Attack, Portishead, trip-hop: boom-bap drums, dusty kit, driven bass riff, rhodes, vinyl haze.
    - Nine Inch Nails, industrial: hard four-on-the-floor, industrial kit, grind bass, dark pad, drone, high distortion.
    - Board of Canada, Moby, ambient: soft four-on-the-floor, soft kit, pluck arpeggio, warm pad, tape, lots of space.
    - Trent Reznor and Atticus Ross scores, cinematic: half-time, glitch kit, pulse sixteenths, felt piano, static, harmony cold.
    - S.T.A.L.K.E.R., MoozE, dark ambient, post-apocalyptic, Chernobyl: drift drums, metal kit, drone bass held, \
    eerie pad, wind texture, harmony desolate, about 60 to 70 BPM, lots of space, little distortion.
    - LTJ Bukem, Goldie, Roni Size, 90s drum and bass, jungle, liquid: jungle drums, amen kit, reese bass two-step, \
    strings keys, rain texture, harmony liquid, 165 to 175 BPM, medium space.
    - "Darker" means higher darkness and the dark minor or menace harmony; "slower" or "low tempo" means a lower BPM.

    Intros: each bar lasts 240 / BPM seconds. When asked for the start or first seconds of a track, \
    build it up: begin with texture and keys or pads, bring the bass in a bar or two later and the drums \
    last, all within the requested time. Otherwise have everything start on bar 1.
    """

    func interpret(_ prompt: String) async throws -> GrooveSpec {
        let session = LanguageModelSession(instructions: Self.instructions)
        let reference = ArtistReference.match(prompt)
        // Spelling the reference out in the request makes the plan agree with it; the
        // signature parts are then enforced, since the small model doesn't always obey.
        let request = reference.map { prompt + "\n\nReference sound for \($0.name): \($0.description)." } ?? prompt
        var spec = try await session.respond(to: request, generating: GrooveSpec.self).content
        reference?.apply(to: &spec)
        spec.fitIntro(toSecondsIn: prompt)
        return spec
    }
}

/// Artists whose signature sounds the on-device model can't be trusted to know.
struct ArtistReference {
    let names: [String]
    let drums: String?, drumKit: String?, bassSound: String?, bassPattern: String?
    let keys: String?, texture: String?

    var name: String { names[0] }

    var description: String {
        [drums.map { "\($0) drums" }, drumKit.map { "\($0) kit" },
         bassSound.map { "\($0) bass" }, bassPattern.map { "\($0) bass pattern" },
         keys.map { "\($0) keys" }, texture.map { "\($0) texture" }]
            .compactMap { $0 }.joined(separator: ", ")
    }

    func apply(to spec: inout GrooveSpec) {
        if let drums { spec.drums = drums }
        if let drumKit { spec.drumKit = drumKit }
        if let bassSound { spec.bassSound = bassSound }
        if let bassPattern { spec.bassPattern = bassPattern }
        if let keys { spec.keys = keys }
        if let texture { spec.texture = texture }
    }

    static func match(_ prompt: String) -> ArtistReference? {
        let p = prompt.lowercased()
        return all.first { ref in ref.names.contains { p.contains($0) } }
    }

    static let all: [ArtistReference] = [
        ArtistReference(names: ["the prodigy", "prodigy"], drums: "breakbeat", drumKit: "industrial",
                        bassSound: "grind", bassPattern: "rolling", keys: nil, texture: "drone"),
        ArtistReference(names: ["chemical brothers"], drums: "breakbeat", drumKit: "industrial",
                        bassSound: "grind", bassPattern: "rolling", keys: nil, texture: nil),
        ArtistReference(names: ["massive attack", "mezzanine", "portishead", "tricky"], drums: "boom-bap", drumKit: "dusty",
                        bassSound: "driven", bassPattern: "riff", keys: "rhodes", texture: "vinyl haze"),
        ArtistReference(names: ["nine inch nails", "nin"], drums: "hard four-on-the-floor", drumKit: "industrial",
                        bassSound: "grind", bassPattern: "rolling", keys: "dark pad", texture: "drone"),
        ArtistReference(names: ["board of canada", "boards of canada", "moby"], drums: "soft four-on-the-floor", drumKit: "soft",
                        bassSound: "pluck", bassPattern: "arpeggio", keys: "warm pad", texture: "tape"),
        ArtistReference(names: ["stalker", "s.t.a.l.k.e.r", "mooze", "radwind", "chernobyl", "dark ambient"], drums: "drift", drumKit: "metal",
                        bassSound: "drone", bassPattern: "held", keys: "eerie pad", texture: "wind"),
        ArtistReference(names: ["ltj bukem", "bukem", "goldie", "roni size", "drum and bass", "drum & bass", "drum n bass", "d&b", "dnb", "jungle"],
                        drums: "jungle", drumKit: "amen", bassSound: "reese", bassPattern: "two-step", keys: "strings", texture: "rain"),
        ArtistReference(names: ["reznor", "atticus", "social network"], drums: "half-time", drumKit: "glitch",
                        bassSound: "pulse", bassPattern: "sixteenths", keys: "felt piano", texture: "static"),
    ]
}

// MARK: - Spec → settings

extension GrooveSpec {
    /// "first 10 sec" and the like: squeeze the entry bars so the whole build-up happens
    /// within that time, keeping the order parts come in.
    mutating func fitIntro(toSecondsIn prompt: String) {
        let pattern = #/(\d+)\s*(s|sec|secs|second|seconds)\b/#
        guard let m = prompt.lowercased().firstMatch(of: pattern), let seconds = Double(m.1), seconds > 0 else { return }
        let barSeconds = 240 / Double(max(bpm, 1))
        let lastBar = max(Int(seconds / barSeconds) - 1, 0) + 1     // 1-based bar that still starts in time
        let entries = [drumsEnter, bassEnter, keysEnter, textureEnter]
        guard let latest = entries.max(), latest > lastBar else { return }
        func squeeze(_ b: Int) -> Int { 1 + Int((Double(b - 1) * Double(lastBar - 1) / Double(latest - 1)).rounded()) }
        (drumsEnter, bassEnter, keysEnter, textureEnter) =
            (squeeze(drumsEnter), squeeze(bassEnter), squeeze(keysEnter), squeeze(textureEnter))
    }

    var recipe: Recipe {
        func style(_ value: String, _ names: [String]) -> Style? {
            names.firstIndex(of: value).flatMap { Style(rawValue: $0) }
        }
        let harmonyStyle = style(harmony, ["dark minor", "menace", "dreamy", "cold", "desolate", "liquid"]) ?? .tripHop
        var r = Recipe.preset(harmonyStyle)
        let keys = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        r.key = keys.firstIndex(of: key) ?? r.key
        r.drums = ["boom-bap", "hard four-on-the-floor", "soft four-on-the-floor", "half-time", "breakbeat", "drift", "jungle"]
            .firstIndex(of: drums).flatMap { DrumGroove(rawValue: $0) }
        r.kit = style(drumKit, ["dusty", "industrial", "soft", "glitch", "metal", "amen"]) ?? harmonyStyle
        r.sub = sub
        r.bassSound = style(bassSound, ["driven", "grind", "pluck", "pulse", "drone", "reese"])
        r.bassPattern = style(bassPattern, ["riff", "rolling", "arpeggio", "sixteenths", "held", "two-step"]) ?? harmonyStyle
        r.keys = style(self.keys, ["rhodes", "dark pad", "warm pad", "felt piano", "eerie pad", "strings"])
        r.texture = style(texture, ["vinyl haze", "drone", "tape", "static", "wind", "rain"])
        let bar = { (b: Int) in min(max(b - 1, 0), 7) }
        var enter = [bar(drumsEnter), bar(bassEnter), bar(bassEnter), bar(keysEnter), bar(textureEnter)]
        // Something always plays from bar 1: shift the whole build so the first part starts there.
        let first = enter.min() ?? 0
        enter = enter.map { $0 - first }
        r.enter = enter
        return r
    }

    var tone: Double { 0.9 - Double(min(max(darkness, 0), 10)) * 0.065 }      // 0.9 … 0.25
    var grit: Double { Double(min(max(distortion, 0), 10)) * 0.07 }           // 0 … 0.7
    var spaceAmount: Double { Double(min(max(space, 0), 10)) / 10 }
}
