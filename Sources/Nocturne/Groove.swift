import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

struct Track: Identifiable, Codable {
    let id: Int
    var volume: Double = 0.8
    var muted = false
}

/// The app's model: owns the audio graph and mirrors the synth's controls for the UI.
@MainActor @Observable
final class Groove {
    var style: Style = .tripHop {
        didSet {
            guard style != oldValue, !restoring else { return }
            if manual { manualRecipe = .preset(style) }     // picking a style starts manual from it
            loadStyle()
        }
    }
    /// Manual mode: every part is set by hand (or by a prompt) instead of by the style.
    var manual = false {
        didSet {
            guard manual != oldValue, !restoring else { return }
            if manual && !hasManualRecipe { manualRecipe = .preset(style); hasManualRecipe = true }
            rebuild()
        }
    }
    /// The hand-made setup; kept while manual mode is off so switching back restores it.
    var manualRecipe: Recipe = .preset(.tripHop) {
        didSet { if manual && manualRecipe != oldValue && !restoring { rebuild(keepingEditsFrom: oldValue) } }
    }
    var recipe: Recipe { manual ? manualRecipe : .preset(style) }

    /// The prompt is being interpreted.
    private(set) var isComposing = false
    /// What the last prompt came up with, or why it failed.
    private(set) var composeNote: String?
    private(set) var composeFailed = false
    /// The prompt field has focus, so bare-key shortcuts (Space) must leave it alone.
    var promptFocused = false
    var isPlaying = false {
        didSet {
            synth.playing = isPlaying
            if !isPlaying && isRecording { stopRecording() }
        }
    }
    var bpm: Double = 86 { didSet { synth.bpm = Float(bpm); updateFX() } }
    var swing: Double = 0.35 { didSet { synth.swing = Float(swing) } }
    var tone: Double = 0.55 { didSet { synth.tone = Float(tone) } }
    var grit: Double = 0.15 { didSet { synth.grit = Float(grit) } }
    var space: Double = 0.45 { didSet { updateFX() } }
    var volume: Double = 0.8 { didSet { pushMaster() } }
    /// Silences everything (playback and recordings) without touching the Volume knob.
    var muteAll = false { didSet { pushMaster() } }
    var tracks: [Track] = [
        Track(id: 0),
        Track(id: 1),
        Track(id: 2),
        Track(id: 3),
        Track(id: 4),
    ] { didSet { pushGains() } }

    private(set) var step = -1
    private(set) var bar = 0
    private(set) var levels = [Double](repeating: 0, count: Synth.trackCount)
    private(set) var pattern: Pattern
    private(set) var isRecording = false
    private(set) var recordingStarted: Date?
    /// True from stopping a take until it has been saved or discarded.
    private(set) var isSavingTake = false
    private(set) var lastTakeDuration: TimeInterval = 0

    var currentChord: String { pattern.chordNames[isPlaying ? bar : 0] }

    @ObservationIgnored let synth: Synth
    @ObservationIgnored private var seed: UInt64 = .random(in: 0...UInt64.max)
    /// The seed the current preset was loaded with, so Reset can bring back that exact pattern.
    @ObservationIgnored private var presetSeed: UInt64 = 0
    @ObservationIgnored private var hasManualRecipe = false
    /// Set while a saved project is applied, so property observers don't regenerate.
    @ObservationIgnored private var restoring = false
    /// Where the current project was opened from or last saved to.
    private(set) var fileURL: URL?
    @ObservationIgnored private let interpreter: PromptInterpreter = AppleInterpreter()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let delay = AVAudioUnitDelay()
    @ObservationIgnored private let reverb = AVAudioUnitReverb()
    /// Last stage: catches peaks the reverb and delay add on top of the synth's own soft clip.
    @ObservationIgnored private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private let recorder = Recorder()

    init() {
        var sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sr <= 0 { sr = 48_000 }
        let first = Pattern.make(.tripHop, seed: .random(in: 0...UInt64.max))
        pattern = first
        synth = Synth(sampleRate: Float(sr), pattern: first)

        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let source = Groove.makeSource(synth, format: format)
        engine.attach(source)
        engine.attach(delay)
        engine.attach(reverb)
        engine.attach(limiter)
        engine.connect(source, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, -1.5, 0)
        delay.feedback = 38
        delay.lowPassCutoff = 2600

        loadStyle()
        pushGains()
        pushMaster()
        do { try engine.start() } catch { NSLog("Nocturne: audio engine failed to start: \(error)") }

        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        // Pick up where the last session left off, and save it again on quit.
        if let data = try? Data(contentsOf: Groove.lastSessionURL),
           let project = try? JSONDecoder().decode(Project.self, from: data) {
            restore(project)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveLastSession() }
        }
    }

    /// Built outside the main actor so the render block carries no actor isolation:
    /// it runs on the real-time audio thread.
    nonisolated private static func makeSource(_ synth: Synth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count >= 2,
                  let l = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(Int(frames), l, r)
            return noErr
        }
    }

    // MARK: Recording

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    /// Records the final mix to a temporary WAV; playback starts with it.
    func startRecording() {
        guard !isRecording, !isSavingTake else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nocturne-\(UUID().uuidString).wav")
        do {
            try recorder.start(on: engine.mainMixerNode, writingTo: url)
        } catch {
            NSLog("Nocturne: could not start recording: \(error)")
            return
        }
        isRecording = true
        recordingStarted = .now
        if !isPlaying { isPlaying = true }
    }

    /// Ends the take. Capture runs on for a couple of seconds so reverb and delay tails
    /// aren't chopped off, then `save` decides where it goes (nil asks with a save panel).
    func stopRecording(tail: Double = 2, save destination: URL? = nil) {
        guard isRecording else { return }
        lastTakeDuration = recordingStarted.map { Date.now.timeIntervalSince($0) } ?? 0
        isRecording = false
        recordingStarted = nil
        isSavingTake = true
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH.mm"
        let suggestedName = "Nocturne \(style.title) \(stamp.string(from: .now))"
        DispatchQueue.main.asyncAfter(deadline: .now() + tail) { [self] in
            guard let take = recorder.stop(on: engine.mainMixerNode) else { isSavingTake = false; return }
            if let destination {
                Groove.move(take, to: destination)
                isSavingTake = false
            } else {
                presentSavePanel(for: take, name: suggestedName)
            }
        }
    }

    private func presentSavePanel(for take: URL, name: String) {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = name + ".wav"
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let dest = panel.url {
                Groove.move(take, to: dest)
            } else {
                try? FileManager.default.removeItem(at: take)
            }
            self?.isSavingTake = false
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private static func move(_ take: URL, to dest: URL) {
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)      // the save panel already confirmed replacing it
            }
            try FileManager.default.moveItem(at: take, to: dest)
        } catch {
            NSLog("Nocturne: could not save recording: \(error)")
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Pattern

    /// Regenerates the pattern from the current recipe, keeping the random seed so
    /// changing one part doesn't reshuffle the others. Given the previous recipe, parts
    /// whose settings didn't change keep their current notes, including hand edits.
    private func rebuild(keepingEditsFrom old: Recipe? = nil) {
        var p = Pattern.make(recipe, seed: seed)
        if let old {
            let cur = pattern, new = recipe
            if old.drums == new.drums {
                (p.kick, p.snare, p.hat, p.open, p.perc) = (cur.kick, cur.snare, cur.hat, cur.open, cur.perc)
            }
            if old.harmony == new.harmony && old.key == new.key {
                (p.chords, p.chordNames, p.bassRoots) = (cur.chords, cur.chordNames, cur.bassRoots)
                if old.bassPattern == new.bassPattern && old.sub == new.sub { p.bass = cur.bass }
                if old.bassPattern == new.bassPattern && (old.bassSound == nil) == (new.bassSound == nil) { p.line = cur.line }
                if old.keys == new.keys { (p.comp, p.melody) = (cur.comp, cur.melody) }
            }
        }
        pattern = p
        synth.setPattern(pattern)
        reverb.loadFactoryPreset([.largeHall2, .largeChamber, .cathedral, .mediumHall, .cathedral][recipe.main.rawValue])
        updateFX()
    }

    /// Applies a hand edit (step editor, chord swap) to the playing pattern.
    func edit(_ change: (inout Pattern) -> Void) {
        var p = pattern
        change(&p)
        pattern = p
        synth.setPattern(p)
    }

    // MARK: Projects

    struct Project: Codable {
        var version = 1
        var style: Style
        var manual: Bool
        var manualRecipe: Recipe
        var pattern: Pattern
        var seed: UInt64
        var presetSeed: UInt64?
        var bpm, swing, tone, grit, space, volume: Double
        var tracks: [Track]
    }

    static let fileType = UTType(filenameExtension: "nocturne", conformingTo: .json) ?? .json

    var project: Project {
        Project(style: style, manual: manual, manualRecipe: manualRecipe, pattern: pattern, seed: seed,
                presetSeed: presetSeed,
                bpm: bpm, swing: swing, tone: tone, grit: grit, space: space, volume: volume, tracks: tracks)
    }

    /// Puts everything back exactly as saved: the pattern as it was, not regenerated.
    func restore(_ p: Project) {
        restoring = true
        style = p.style
        manualRecipe = p.manualRecipe
        hasManualRecipe = true
        manual = p.manual
        seed = p.seed
        presetSeed = p.presetSeed ?? p.seed
        bpm = p.bpm; swing = p.swing; tone = p.tone; grit = p.grit; space = p.space; volume = p.volume
        if p.tracks.count == tracks.count { tracks = p.tracks }
        pattern = p.pattern
        synth.setPattern(pattern)
        reverb.loadFactoryPreset([.largeHall2, .largeChamber, .cathedral, .mediumHall, .cathedral][recipe.main.rawValue])
        updateFX()
        restoring = false
    }

    func save(as saveAs: Bool = false) {
        if !saveAs, let fileURL {
            write(to: fileURL)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save Project"
        panel.allowedContentTypes = [Groove.fileType]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Nocturne \(style.title).nocturne"
        panel.canCreateDirectories = true
        sheet(panel) { [weak self] ok in
            guard ok, let url = panel.url, let self else { return }
            if self.write(to: url) { self.fileURL = url }
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.allowedContentTypes = [Groove.fileType]
        sheet(panel) { [weak self] ok in
            guard ok, let url = panel.url, let self else { return }
            do {
                let project = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
                self.isPlaying = false
                self.restore(project)
                self.fileURL = url
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @discardableResult
    private func write(to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(project).write(to: url, options: .atomic)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    private func sheet(_ panel: NSSavePanel, _ done: @escaping (Bool) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            panel.beginSheetModal(for: window) { done($0 == .OK) }
        } else {
            done(panel.runModal() == .OK)
        }
    }

    /// Per app (bundle id), so the test build never touches the real app's session.
    static var lastSessionURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nocturne", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Last Session.nocturne")
    }

    func saveLastSession() {
        if let data = try? JSONEncoder().encode(project) { try? data.write(to: Groove.lastSessionURL, options: .atomic) }
    }

    func trackName(_ i: Int) -> String {
        manual ? ["Drums", "Sub", "Bass", "Keys", "Texture"][i] : style.trackNames[i]
    }

    // MARK: Prompt

    /// Interprets a description, switches to manual mode with the result and plays it
    /// from the top so a build-up is heard.
    func compose(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isComposing else { return }
        if let reason = AppleInterpreter.unavailableReason {
            composeNote = reason
            composeFailed = true
            return
        }
        isComposing = true
        composeNote = nil
        Task {
            defer { isComposing = false }
            do {
                let spec = try await interpreter.interpret(text)
                seed = .random(in: 0...UInt64.max)
                hasManualRecipe = true
                if manual { manualRecipe = spec.recipe } else { manualRecipe = spec.recipe; manual = true }
                bpm = Double(spec.bpm)
                swing = spec.recipe.drums == .breakbeat ? 0.1 : spec.recipe.kit.defaults.swing
                tone = spec.tone
                grit = spec.grit
                space = spec.spaceAmount
                composeNote = spec.plan
                composeFailed = false
                if isPlaying { synth.restart() } else { isPlaying = true }
            } catch {
                composeNote = "Couldn't create that: \(error.localizedDescription)"
                composeFailed = true
            }
        }
    }

    /// Notes of the chord currently sounding (bar 1's chord while stopped).
    var chordNotes: Set<Int> { Set(pattern.chords[isPlaying ? bar : 0]) }

    func noteOn(_ midi: Int) { synth.noteOn(midi) }
    func noteOff(_ midi: Int) { synth.noteOff(midi) }

    private func loadStyle() {
        applyDefaultKnobs()
        seed = .random(in: 0...UInt64.max)
        presetSeed = seed
        rebuild()
    }

    private func applyDefaultKnobs() {
        let d = style.defaults
        bpm = d.bpm
        swing = d.swing
        tone = d.tone
        grit = d.grit
        space = d.space
    }

    /// Puts the current preset back exactly as it started: the same pattern (not a new
    /// variation), default knobs, faders at 80% and nothing muted. Manual mode turns off;
    /// its setup is kept for when it's switched back on. Mute All is left alone.
    func resetPreset() {
        restoring = true            // one rebuild below instead of one per change
        manual = false
        restoring = false
        applyDefaultKnobs()
        volume = 0.8
        tracks = tracks.map { Track(id: $0.id) }
        seed = presetSeed
        rebuild()
    }

    private func updateFX() {
        reverb.wetDryMix = Float(space * 55)
        delay.wetDryMix = Float(space * [30, 12, 35, 15, 25][recipe.main.rawValue])     // dub delay for trip-hop and dreamy
        delay.delayTime = 0.75 * 60 / bpm      // dotted eighth
    }

    private func pushMaster() { synth.master = muteAll ? 0 : Float(volume) }

    private func pushGains() {
        for t in tracks { synth.gains[t.id] = t.muted ? 0 : Float(t.volume) }
    }

    private func tick() {
        if synth.uiStep != step { step = synth.uiStep }
        if synth.uiBar != bar { bar = synth.uiBar }
        let new = (0..<Synth.trackCount).map { Double(min(1, synth.meters[$0] * 2.5)) }
        if zip(new, levels).contains(where: { abs($0 - $1) > 0.02 }) { levels = new }
    }
}
