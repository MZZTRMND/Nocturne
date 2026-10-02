import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

struct Track: Identifiable {
    let id: Int
    var volume: Double = 0.8
    var muted = false
}

/// The app's model: owns the audio graph and mirrors the synth's controls for the UI.
@MainActor @Observable
final class Groove {
    var style: Style = .tripHop {
        didSet {
            guard style != oldValue else { return }
            if manual { manualRecipe = .preset(style) }     // picking a style starts manual from it
            loadStyle()
        }
    }
    /// Manual mode: every part is set by hand (or by a prompt) instead of by the style.
    var manual = false {
        didSet {
            guard manual != oldValue else { return }
            if manual && !hasManualRecipe { manualRecipe = .preset(style); hasManualRecipe = true }
            rebuild()
        }
    }
    /// The hand-made setup; kept while manual mode is off so switching back restores it.
    var manualRecipe: Recipe = .preset(.tripHop) {
        didSet { if manual && manualRecipe != oldValue { rebuild() } }
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
    /// The current (or last) take's mix level, sampled 10× a second, for the timeline.
    private(set) var takeLevels: [Double] = []
    private(set) var lastTakeDuration: TimeInterval = 0

    var currentChord: String { pattern.chordNames[isPlaying ? bar : 0] }

    @ObservationIgnored let synth: Synth
    @ObservationIgnored private var seed: UInt64 = .random(in: 0...UInt64.max)
    @ObservationIgnored private var hasManualRecipe = false
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
    @ObservationIgnored private var tickCount = 0

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
        takeLevels = []
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
    /// changing one part doesn't reshuffle the others.
    private func rebuild() {
        pattern = Pattern.make(recipe, seed: seed)
        synth.setPattern(pattern)
        reverb.loadFactoryPreset([.largeHall2, .largeChamber, .cathedral, .mediumHall][recipe.main.rawValue])
        updateFX()
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
        let d = style.defaults
        bpm = d.bpm
        swing = d.swing
        tone = d.tone
        grit = d.grit
        space = d.space
        seed = .random(in: 0...UInt64.max)
        rebuild()
    }

    private func updateFX() {
        reverb.wetDryMix = Float(space * 55)
        delay.wetDryMix = Float(space * [30, 12, 35, 15][recipe.main.rawValue])     // dub delay for trip-hop and dreamy
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
        tickCount += 1
        if isRecording && tickCount % 3 == 0 {
            takeLevels.append(new.max() ?? 0)
            if takeLevels.count > 600 { takeLevels.removeFirst(takeLevels.count - 600) }
        }
    }
}
