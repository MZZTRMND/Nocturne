import AVFoundation
import Observation

struct Track: Identifiable {
    let id: Int
    let icon: String
    var volume: Double = 0.8
    var muted = false
}

/// The app's model: owns the audio graph and mirrors the synth's controls for the UI.
@MainActor @Observable
final class Groove {
    var style: Style = .tripHop {
        didSet { if style != oldValue { loadStyle() } }
    }
    var isPlaying = false { didSet { synth.playing = isPlaying } }
    var bpm: Double = 86 { didSet { synth.bpm = Float(bpm); updateFX() } }
    var swing: Double = 0.35 { didSet { synth.swing = Float(swing) } }
    var tone: Double = 0.55 { didSet { synth.tone = Float(tone) } }
    var grit: Double = 0.15 { didSet { synth.grit = Float(grit) } }
    var space: Double = 0.45 { didSet { updateFX() } }
    var volume: Double = 0.8 { didSet { synth.master = Float(volume) } }
    var tracks: [Track] = [
        Track(id: 0, icon: "square.grid.3x3.fill"),
        Track(id: 1, icon: "waveform"),
        Track(id: 2, icon: "guitars.fill"),
        Track(id: 3, icon: "pianokeys"),
        Track(id: 4, icon: "sparkles"),
    ] { didSet { pushGains() } }

    private(set) var step = -1
    private(set) var bar = 0
    private(set) var levels = [Double](repeating: 0, count: Synth.trackCount)
    private(set) var pattern: Pattern

    var currentChord: String { pattern.chordNames[isPlaying ? bar : 0] }

    @ObservationIgnored let synth: Synth
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let delay = AVAudioUnitDelay()
    @ObservationIgnored private let reverb = AVAudioUnitReverb()
    @ObservationIgnored private var poll: Timer?

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
        engine.connect(source, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        delay.feedback = 38
        delay.lowPassCutoff = 2600

        loadStyle()
        pushGains()
        synth.master = Float(volume)
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

    private func loadPattern() {
        pattern = Pattern.make(style, seed: .random(in: 0...UInt64.max))
        synth.setPattern(pattern)
    }

    func trackName(_ i: Int) -> String { style.trackNames[i] }

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
        reverb.loadFactoryPreset([.largeHall2, .largeChamber, .cathedral][style.rawValue])
        space = d.space
        loadPattern()
    }

    private func updateFX() {
        reverb.wetDryMix = Float(space * 55)
        delay.wetDryMix = Float(space * [30, 12, 35][style.rawValue])     // dub delay for trip-hop and techno
        delay.delayTime = 0.75 * 60 / bpm      // dotted eighth
    }

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
