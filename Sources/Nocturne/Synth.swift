import Foundation

private let twoPi = Float.pi * 2

@inline(__always) func mtof(_ m: Int) -> Float { 440 * powf(2, Float(m - 69) / 12) }
@inline(__always) private func wrap(_ x: inout Float) { if x >= 1 { x -= floorf(x) } }

// MARK: - Building blocks

/// Zero-delay-feedback state variable filter (Simper). `k` = 1/Q.
struct SVF {
    var ic1: Float = 0, ic2: Float = 0
    var g: Float = 0.1, k: Float = 1

    mutating func set(_ fc: Float, k: Float, sr: Float) {
        g = tanf(.pi * min(max(fc, 20), sr * 0.45) / sr)
        self.k = k
    }

    @inline(__always)
    mutating func tick(_ x: Float) -> (lp: Float, bp: Float, hp: Float) {
        let a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1, x - k * v1 - v2)
    }
}

struct Noise {
    var s: UInt32 = 0x1234_5678
    @inline(__always) mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Float(Int32(bitPattern: s)) / Float(Int32.max)
    }
}

// MARK: - Voices

struct Kick {
    var t: Float = 10, vel: Float = 0, ph: Float = 0

    mutating func trigger(_ v: Float) { t = 0; vel = v; ph = 0 }

    mutating func next(_ s: Style, _ dt: Float, _ n: Float) -> Float {
        guard t < 1.5 else { return 0 }
        // A fast pitch drop gives the attack, the saturated sine body gives the weight,
        // and a few ms of noise on top is the beater click.
        let f, a: Float
        switch s {
        case .tripHop: f = 44 + 130 * expf(-t * 26); a = expf(-t * 4)
        case .industrial: f = 40 + 190 * expf(-t * 38); a = expf(-t * 3.8)
        case .techno: f = 46 + 110 * expf(-t * 28); a = expf(-t * 5)
        }
        ph += f * dt; wrap(&ph)
        let body = sinf(twoPi * ph) * a
        let click = t < 0.004 ? n * (1 - t / 0.004) * 0.45 : 0
        let out: Float
        switch s {
        case .tripHop: out = tanhf(body * 2.4) + click * 0.6
        case .industrial: out = tanhf(body * 4) * 0.8 + click
        case .techno: out = tanhf(body * 1.8) * 0.85 + click * 0.3     // round, soft beater
        }
        t += dt
        return out * vel
    }
}

struct Snare {
    var t: Float = 10, vel: Float = 0, ph: Float = 0, bp = SVF()

    mutating func trigger(_ v: Float, _ s: Style, sr: Float) {
        t = 0; vel = v; ph = 0
        switch s {
        case .tripHop: bp.set(1500, k: 0.8, sr: sr)
        case .industrial: bp.set(1300, k: 0.6, sr: sr)
        case .techno: bp.set(1500, k: 0.9, sr: sr)
        }
    }

    mutating func next(_ s: Style, _ dt: Float, _ n: Float) -> Float {
        guard t < 1.2 else { return 0 }
        let nz = bp.tick(n).bp
        var out: Float
        switch s {
        case .tripHop:      // big, low, roomy snare with a long noise tail, gently clipped
            ph += (150 + 50 * expf(-t * 40)) * dt
            out = tanhf((sinf(twoPi * ph) * expf(-t * 18) * 1.0 + nz * expf(-t * 8) * 2.2) * 1.6)
        case .industrial:   // clap-ish triple burst, crushed
            ph += 160 * dt
            let burst: Float = t < 0.03 ? (fmodf(t, 0.01) < 0.004 ? 1 : 0.3) : 1
            out = tanhf((sinf(twoPi * ph) * expf(-t * 22) * 0.7 + nz * expf(-t * 9) * 2.2 * burst) * 2.5) * 0.8
        case .techno:       // soft, dusty snare
            ph += 190 * dt
            out = (sinf(twoPi * ph) * expf(-t * 25) * 0.5 + nz * expf(-t * 16) * 1.4) * 0.7
        }
        wrap(&ph)
        t += dt
        return out * vel
    }
}

struct Hat {
    var t: Float = 10, vel: Float = 0, decay: Float = 40, hp = SVF()

    mutating func trigger(_ v: Float, decay: Float, cutoff: Float, sr: Float) {
        t = 0; vel = v; self.decay = decay
        hp.set(cutoff, k: 1.2, sr: sr)
    }

    mutating func choke() { decay = max(decay, 150) }

    mutating func next(_ dt: Float, _ n: Float) -> Float {
        guard t < 2 else { return 0 }
        let out = hp.tick(n).hp * expf(-t * decay)
        t += dt
        return out * vel
    }
}

/// Rimshot for trip-hop, FM metal hit for industrial.
struct Perc {
    var t: Float = 10, vel: Float = 0, pc: Float = 0, pm: Float = 0, bp = SVF()

    mutating func trigger(_ v: Float, sr: Float) {
        t = 0; vel = v; pc = 0; pm = 0
        bp.set(2400, k: 1.5, sr: sr)
    }

    mutating func next(_ s: Style, _ dt: Float, _ n: Float) -> Float {
        guard t < 1.5 else { return 0 }
        var out: Float
        if s == .industrial {
            pc += 310 * dt; pm += 437 * dt
            wrap(&pc); wrap(&pm)
            let idx = 3.5 * expf(-t * 5)
            out = tanhf(sinf(twoPi * pc + idx * sinf(twoPi * pm)) * expf(-t * 6) * 2) * 0.6
        } else {
            pc += 410 * dt; wrap(&pc)
            out = (sinf(twoPi * pc) * 0.6 + bp.tick(n).bp * 1.2) * expf(-t * 55)
        }
        t += dt
        return out * vel
    }
}

struct Bass {
    var ph: Float = 0, f: Float = 55, target: Float = 55
    var env: Float = 0, gate = 0, vel: Float = 0, t: Float = 10, lp = SVF()

    mutating func trigger(_ freq: Float, samples: Int, vel: Float) {
        target = freq
        if env < 0.02 { f = freq }
        gate = samples; self.vel = vel; t = 0
    }

    mutating func next(_ dt: Float, atk: Float, rel: Float) -> Float {
        f += (target - f) * 0.0025
        ph += f * dt; wrap(&ph)
        if gate > 0 { gate -= 1; env += (1 - env) * atk } else { env *= rel }
        t += dt
        if gate == 0 && env < 1e-5 { return 0 }
        return (sinf(twoPi * ph) + 0.18 * sinf(2 * twoPi * ph)) * 0.9 * env * vel
    }
}

/// The audible line: a warm bass pluck (trip-hop), a crushed saw (industrial) or a soft,
/// plucked arpeggio (techno). A note that arrives while the previous one is still held
/// slides into it without restarting the filter envelope.
struct LineBass {
    var ph: Float = 0, f: Float = 110, target: Float = 110
    var env: Float = 0, gate = 0, vel: Float = 0, t: Float = 10, accent = false, lp = SVF()

    mutating func trigger(_ freq: Float, samples: Int, vel: Float) {
        let slide = gate > 0
        target = freq
        if !slide { f = freq; t = 0 }
        gate = samples; self.vel = vel; accent = vel > 0.9
    }

    mutating func next(_ s: Style, _ dt: Float, sr: Float, atk: Float, rel: Float, pitch: Float) -> Float {
        f += (target - f) * 0.004
        ph += f * pitch * dt; wrap(&ph)
        if gate > 0 { gate -= 1; env += (1 - env) * atk } else { env *= rel }
        t += dt
        if gate == 0 && env < 1e-5 { return 0 }
        let out: Float
        switch s {
        case .tripHop:      // brooding, driven square/saw blend through a slow-closing filter
            lp.set(220 + 900 * expf(-t * 5), k: 0.7, sr: sr)
            let src = 0.5 * (ph < 0.5 ? 1 : -1) + 0.5 * (2 * ph - 1)
            out = tanhf(lp.tick(src).lp * 2.5) * 0.5
        case .industrial:
            lp.set(110 + 2600 * expf(-t * 20), k: 0.35, sr: sr)
            out = tanhf(lp.tick(2 * ph - 1).lp * 3) * 0.7
        case .techno:       // triangle/saw blend, gently filtered, decaying like a pluck
            lp.set(500 + 1800 * expf(-t * 7), k: 0.9, sr: sr)
            out = lp.tick(0.6 * (4 * abs(ph - 0.5) - 1) + 0.4 * (2 * ph - 1)).lp * 0.6 * expf(-t * 2.5)
        }
        return out * env * vel
    }
}

/// The keys part: electric piano, pad or stab depending on the style.
struct Key {
    var on = false, f: Float = 0, pan: Float = 0
    /// Pad attack time; live-played notes use a short one so they respond immediately.
    var attack: Float = 0.7
    var pc: Float = 0, pm: Float = 0, p2: Float = 0
    var t: Float = 0, rt: Float = 0, gate = 0, vel: Float = 0

    mutating func next(_ s: Style, _ dt: Float, pitch: Float = 1) -> Float {
        let relEnv: Float
        if gate > 0 { gate -= 1; relEnv = 1 } else { rt += dt; relEnv = expf(-rt * [7, 2.5, 1.6][s.rawValue]) }
        let amp, out: Float
        switch s {
        case .industrial:   // slow detuned saw pad with a sub-octave sine
            pc += f * 1.006 * dt; pm += f * 0.994 * dt; p2 += f * 0.5 * dt
            wrap(&pc); wrap(&pm); wrap(&p2)
            amp = min(1, t / attack)
            out = ((2 * pc - 1) + (2 * pm - 1)) * 0.5 + sinf(twoPi * p2) * 0.4
        case .techno:       // warm, wide pad: detuned saws over a soft triangle
            let pf = f * pitch
            pc += pf * 1.005 * dt; pm += pf * 0.995 * dt; p2 += pf * dt
            wrap(&pc); wrap(&pm); wrap(&p2)
            amp = min(1, t / attack)
            out = ((2 * pc - 1) + (2 * pm - 1)) * 0.35 + (4 * abs(p2 - 0.5) - 1) * 0.5
        case .tripHop:      // FM electric piano
            pc += f * dt; pm += f * dt
            wrap(&pc); wrap(&pm)
            let idx = 0.8 * expf(-t * 4) + 0.1
            out = sinf(twoPi * pc + idx * sinf(twoPi * pm))
            amp = min(1, t / 0.003) * expf(-t * 0.7)
        }
        t += dt
        let a = amp * relEnv * vel
        if relEnv < 0.0005 || (s == .tripHop && t > 0.1 && a < 0.00005) { on = false }
        return out * a
    }
}

/// One-shot sounds for the drum pads that the pattern doesn't use.
struct PadSound {
    enum Kind { case clap, tom(Float), shaker, cowbell, crash, boom, zap, riser }

    let kind: Kind
    var t: Float = 10, vel: Float = 0, ph: Float = 0, ph2: Float = 0, sr: Float = 48_000
    var f = SVF()
    var mph = SIMD8<Float>(repeating: 0)
    static let metal = SIMD8<Float>(205.3, 304.4, 369.6, 522.7, 540.0, 800.0, 0, 0) * 2.1

    init(_ kind: Kind) { self.kind = kind }

    mutating func trigger(_ v: Float, sr: Float) {
        t = 0; vel = v; ph = 0; ph2 = 0; self.sr = sr
        switch kind {
        case .clap: f.set(1400, k: 0.7, sr: sr)
        case .shaker: f.set(6500, k: 1, sr: sr)
        case .cowbell: f.set(900, k: 0.5, sr: sr)
        case .crash: f.set(5000, k: 1, sr: sr)
        default: break
        }
    }

    mutating func next(_ dt: Float, _ n: Float) -> Float {
        guard t < 3 else { return 0 }
        var out: Float
        switch kind {
        case .clap:
            let burst: Float = t < 0.03 ? (fmodf(t, 0.01) < 0.004 ? 1 : 0.25) : 1
            out = tanhf(f.tick(n).bp * expf(-t * 12) * 3 * burst) * 0.8
        case .tom(let base):
            ph += base * (1 + 0.6 * expf(-t * 18)) * dt; wrap(&ph)
            out = sinf(twoPi * ph) * expf(-t * 7) + n * 0.08 * expf(-t * 40)
        case .shaker:
            out = f.tick(n).hp * min(1, t / 0.012) * expf(-t * 28) * 0.95
        case .cowbell:
            ph += 540 * dt; ph2 += 800 * dt; wrap(&ph); wrap(&ph2)
            let sq: Float = (ph < 0.5 ? 1 : -1) + (ph2 < 0.5 ? 1 : -1)
            out = f.tick(sq * 0.5).bp * expf(-t * 9) * 0.65
        case .crash:
            mph += PadSound.metal * dt
            mph -= mph.rounded(.down)
            let sq = SIMD8<Float>(repeating: -1).replacing(with: 1, where: mph .< 0.5)
            out = f.tick((sq.sum() - 2) * 0.1 + n * 0.6).hp * expf(-t * 1.6) * 1.2
        case .boom:     // long 808 sub with a drop
            ph += (48 + 60 * expf(-t * 20)) * dt; wrap(&ph)
            out = tanhf(sinf(twoPi * ph) * 2.5) * expf(-t * 1.5) * 1.3
        case .zap:      // laser: fast downward sweep
            ph += (80 + 2000 * expf(-t * 25)) * dt; wrap(&ph)
            out = sinf(twoPi * ph) * expf(-t * 8) * 0.5
        case .riser:    // noise swept up over ~1.5 s
            f.set(300 * powf(26, min(t / 1.5, 1)), k: 0.6, sr: sr)
            out = f.tick(n).bp * min(1, t / 1.2) * (t < 1.5 ? 1 : expf(-(t - 1.5) * 8)) * 0.6
        }
        t += dt
        return out * vel
    }
}

// MARK: - Synth

/// Renders the whole band sample by sample on the audio thread. Controls are plain stored
/// properties written from the main thread; the pattern and live notes are handed over
/// through a lock the render thread only ever `try`s, so it never blocks.
final class Synth {
    let sr: Float
    private let dt: Float

    // Controls (main thread writes, render thread reads)
    var playing = false
    var bpm: Float = 86
    var swing: Float = 0.3
    var tone: Float = 0.5
    var grit: Float = 0.2
    var master: Float = 0.8
    /// Target gain per track: drums, sub, bass, keys, texture. 0 when muted.
    static let trackCount = 5
    let gains = UnsafeMutablePointer<Float>.allocate(capacity: Synth.trackCount)

    // Read by the UI
    private(set) var uiStep = -1
    private(set) var uiBar = 0
    let meters = UnsafeMutablePointer<Float>.allocate(capacity: Synth.trackCount)

    private let lock = NSLock()
    private var pending: Pattern?
    private var pattern: Pattern
    /// Live keyboard events (midi, isDown), queued by the main thread.
    private var events: [(Int, Bool)] = []
    /// Drum pad hits (pad index), queued by the main thread.
    private var padEvents: [Int] = []

    /// Pads, bottom-left first. 0–3 and 5 use the style's own drum voices; the rest are
    /// `PadSound`s, except 12 (chord stab) and 13 (bass hit), which play the current chord.
    static let padNames = ["Kick", "Snare", "Hat", "Open Hat",
                           "Clap", "Rim", "Low Tom", "High Tom",
                           "Shaker", "Cowbell", "Crash", "Boom",
                           "Stab", "Bass", "Zap", "Riser"]
    static let padCount = 16
    /// Bumped every time a pad's sound plays, from a click or from the sequencer; the UI
    /// watches these to light the pads.
    let padHits = UnsafeMutablePointer<Int>.allocate(capacity: Synth.padCount)

    private var wasPlaying = false
    private var globalStep = 0
    private var samplesToNext: Float = 0
    private var noise = Noise()
    private var smoothGains = [Float](repeating: 0.8, count: Synth.trackCount)
    private var smoothMaster: Float = 0.8

    private var kick = Kick(), snare = Snare(), hat = Hat(), openHat = Hat(), perc = Perc()
    private var bass = Bass()
    private var line = LineBass()
    private var padSounds: [PadSound] = [
        PadSound(.clap), PadSound(.tom(95)), PadSound(.tom(160)), PadSound(.shaker),
        PadSound(.cowbell), PadSound(.crash), PadSound(.boom), PadSound(.zap), PadSound(.riser),
    ]
    /// Pad index → slot in `padSounds` (-1 = handled by another voice).
    private static let padSlot = [-1, -1, -1, -1, 0, -1, 1, 2, 3, 4, 5, 6, -1, -1, 7, 8]
    private var lastBar = 0
    private var keys = [Key](repeating: Key(), count: 12)
    private var live = [Key](repeating: Key(), count: 10)
    private var liveNote = [Int](repeating: -1, count: 10)
    private var nextPanLeft = true
    private var kickFollow: Float = 0

    private var keysL = SVF(), keysR = SVF(), toneL = SVF(), toneR = SVF()
    private var hissLP = SVF(), droneBP = SVF(), rumbleLP = SVF(), airBP = SVF()
    private var crackle: Float = 0
    private var dronePh: Float = 0, droneF: Float = 41, droneTarget: Float = 41
    private var lfoSlow: Float = 0, lfoTrem: Float = 0, wowPh: Float = 0, flutterPh: Float = 0
    private let atk: Float, rel: Float

    init(sampleRate: Float, pattern: Pattern) {
        sr = sampleRate
        dt = 1 / sampleRate
        self.pattern = pattern
        atk = 1 - expf(-1 / (0.004 * sampleRate))
        rel = expf(-1 / (0.06 * sampleRate))
        for i in 0..<Synth.trackCount { gains[i] = 0.8; meters[i] = 0 }
        events.reserveCapacity(64)
        padEvents.reserveCapacity(64)
        for i in 0..<Synth.padCount { padHits[i] = 0 }
        hissLP.set(3200, k: 1, sr: sr)
        rumbleLP.set(160, k: 0.9, sr: sr)
    }

    deinit {
        gains.deallocate()
        meters.deallocate()
        padHits.deallocate()
    }

    func setPattern(_ p: Pattern) {
        lock.lock()
        pending = p
        lock.unlock()
    }

    func hitPad(_ index: Int) {
        lock.lock()
        padEvents.append(index)
        lock.unlock()
    }

    func noteOn(_ midi: Int) { queue(midi, true) }
    func noteOff(_ midi: Int) { queue(midi, false) }

    private func queue(_ midi: Int, _ down: Bool) {
        lock.lock()
        events.append((midi, down))
        lock.unlock()
    }

    // MARK: Rendering

    func render(_ n: Int, _ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>) {
        if lock.try() {
            if let p = pending { pattern = p; pending = nil }
            for (m, down) in events { down ? startLive(m) : stopLive(m) }
            events.removeAll(keepingCapacity: true)
            for i in padEvents { triggerPad(i, vel: 1) }
            padEvents.removeAll(keepingCapacity: true)
            lock.unlock()
        }

        let isOn = playing
        if isOn && !wasPlaying { globalStep = 0; samplesToNext = 0 }
        if !isOn && wasPlaying { releaseAll(); uiStep = -1 }
        wasPlaying = isOn

        let style = pattern.style
        let cutoff = 250 * powf(80, min(max(tone, 0), 1))
        toneL.set(cutoff, k: 1.1, sr: sr)
        toneR.set(cutoff, k: 1.1, sr: sr)
        let sweep = 0.5 + 0.5 * sinf(twoPi * lfoSlow)
        switch style {
        case .tripHop: keysL.set(1400, k: 0.9, sr: sr)
        case .industrial: keysL.set(300 + 1800 * sweep, k: 0.3, sr: sr)
        case .techno: keysL.set(1100 + 700 * sweep, k: 0.8, sr: sr)
        }
        keysR.g = keysL.g; keysR.k = keysL.k
        droneBP.set(220 + 900 * sweep, k: 0.15, sr: sr)
        airBP.set(3000 + 4000 * sweep, k: 0.8, sr: sr)
        let drive = 1 + grit * 12

        for i in 0..<n {
            if isOn {
                if samplesToNext <= 0 { fireStep() }
                samplesToNext -= 1
            }
            for j in 0..<Synth.trackCount { smoothGains[j] += (gains[j] - smoothGains[j]) * 0.002 }

            // Drums
            let k = kick.next(style, dt, noise.next()) * 1.35
            let sn = snare.next(style, dt, noise.next()) * 0.9
            let hh = hat.next(dt, noise.next()) * 0.4
            let oh = openHat.next(dt, noise.next()) * 0.32
            let pc = perc.next(style, dt, noise.next()) * 0.45
            var pads: Float = 0
            for v in 0..<padSounds.count where padSounds[v].t < 3 { pads += padSounds[v].next(dt, noise.next()) }
            pads *= 0.6
            let dScale: Float = style == .techno ? 0.7 : 1    // ambient: drums sit behind the pad
            let dL = (k + sn + hh * 0.7 + oh * 0.7 + pc * 1.2 + pads) * smoothGains[0] * dScale
            let dR = (k + sn + hh * 1.3 + oh * 1.3 + pc * 0.8 + pads) * smoothGains[0] * dScale

            // Everything else ducks under the kick, so it punches through the mix.
            kickFollow = max(abs(k) * smoothGains[0], kickFollow * 0.9993)
            let duck = 1 - (style == .techno ? 0.2 : 0.4) * min(kickFollow, 1)

            // Tape wow and flutter: a slow, slightly seasick warble on techno's melodic parts.
            var pitch: Float = 1
            if style == .techno {
                wowPh += 0.35 * dt; wrap(&wowPh)
                flutterPh += 6 * dt; wrap(&flutterPh)
                pitch = 1 + 0.0035 * sinf(twoPi * wowPh) + 0.0008 * sinf(twoPi * flutterPh)
            }

            // Sub + bass line
            let b = bass.next(dt, atk: atk, rel: rel) * 0.42 * smoothGains[1] * duck
            let ln = line.next(style, dt, sr: sr, atk: atk, rel: rel, pitch: pitch) * 0.4 * smoothGains[2] * duck

            // Keys: the pattern's chords plus anything played live
            var kL: Float = 0, kR: Float = 0
            for v in 0..<keys.count where keys[v].on {
                let s = keys[v].next(style, dt, pitch: pitch) * 0.11
                kL += s * (1 - keys[v].pan)
                kR += s * (1 + keys[v].pan)
            }
            for v in 0..<live.count where live[v].on {
                let s = live[v].next(style, dt, pitch: pitch) * 0.16
                kL += s
                kR += s
            }
            kL = keysL.tick(kL).lp
            kR = keysR.tick(kR).lp
            if style == .tripHop {
                let tr = sinf(twoPi * lfoTrem)
                kL *= 1 - 0.25 * (0.5 + 0.5 * tr)
                kR *= 1 - 0.25 * (0.5 - 0.5 * tr)
            }
            let kScale: Float = style == .techno ? 1.4 : 1
            kL *= smoothGains[3] * duck * kScale
            kR *= smoothGains[3] * duck * kScale

            // Texture
            var tx: Float
            switch style {
            case .industrial:
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * dt; wrap(&dronePh)
                tx = droneBP.tick(noise.next()).bp * 0.06 + rumbleLP.tick(2 * dronePh - 1).lp * 0.22
            case .techno:   // tape hiss with a little air on top
                tx = hissLP.tick(noise.next()).lp * 0.025 + airBP.tick(noise.next()).bp * 0.02
            case .tripHop:  // vinyl crackle over a low, slowly breathing drone on the root
                if noise.next() > 0.9992 { crackle = 0.3 + 0.3 * noise.next() }
                crackle *= 0.55
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * 2 * dt; wrap(&dronePh)
                let drone = rumbleLP.tick(2 * dronePh - 1).lp * 0.12 + droneBP.tick(noise.next()).bp * 0.025
                tx = crackle * noise.next() + hissLP.tick(noise.next()).lp * 0.02 + drone
            }
            tx *= smoothGains[4]

            lfoSlow += 0.06 * dt; wrap(&lfoSlow)
            lfoTrem += 4.2 * dt; wrap(&lfoTrem)

            meters[0] = max(abs(dL + dR) * 0.5, meters[0] * 0.9997)
            meters[1] = max(abs(b), meters[1] * 0.9997)
            meters[2] = max(abs(ln), meters[2] * 0.9997)
            meters[3] = max(abs(kL + kR) * 0.5, meters[3] * 0.9997)
            meters[4] = max(abs(tx) * 4, meters[4] * 0.9997)

            var l = dL + b + ln + kL + tx
            var r = dR + b + ln + kR + tx
            if grit > 0.001 {
                l += (tanhf(l * drive) * 0.55 - l) * grit
                r += (tanhf(r * drive) * 0.55 - r) * grit
            }
            l = toneL.tick(l).lp
            r = toneR.tick(r).lp
            smoothMaster += (master - smoothMaster) * 0.002     // no clicks on mute/volume jumps
            outL[i] = tanhf(l * smoothMaster)
            outR[i] = tanhf(r * smoothMaster)
        }
    }

    private func fireStep() {
        let bar = (globalStep / 16) % 4, s = globalStep % 16
        let style = pattern.style
        let base = sr * 60 / max(bpm, 30) / 4
        let human = 0.92 + 0.08 * noise.next()

        lastBar = bar
        if pattern.kick[bar][s] > 0 { kick.trigger(pattern.kick[bar][s] * human); padHits[0] &+= 1 }
        if pattern.snare[bar][s] > 0 { snare.trigger(pattern.snare[bar][s] * human, style, sr: sr); padHits[1] &+= 1 }
        if pattern.hat[bar][s] > 0 {
            hat.trigger(pattern.hat[bar][s] * human, decay: [45, 50, 65][style.rawValue],
                        cutoff: style == .tripHop ? 6000 : 7500, sr: sr)
            openHat.choke()
            padHits[2] &+= 1
        }
        if pattern.open[bar][s] > 0 {
            padHits[3] &+= 1
            openHat.trigger(pattern.open[bar][s] * human, decay: [9, 12, 10][style.rawValue], cutoff: 7000, sr: sr)
        }
        if pattern.perc[bar][s] > 0 { perc.trigger(pattern.perc[bar][s] * human, sr: sr); padHits[5] &+= 1 }
        if let h = pattern.bass[bar][s] {
            bass.trigger(mtof(h.midi), samples: Int(Float(h.len) * base * 0.92), vel: h.vel)
        }
        if let h = pattern.line[bar][s] {
            line.trigger(mtof(h.midi), samples: Int(Float(h.len) * base * 0.92), vel: h.vel)
        }
        if let h = pattern.comp[bar][s] {
            let len = Int(Float(h.len) * base * 0.95)
            for m in pattern.chords[bar] {
                triggerKey(m, samples: len, vel: h.vel * (0.85 + 0.15 * noise.next()))
            }
        }
        if s == 0 { droneTarget = mtof(pattern.bassRoots[bar] - 12) }

        uiStep = s
        uiBar = bar
        globalStep += 1
        samplesToNext += base * (globalStep % 2 == 1 ? 1 + swing / 3 : 1 - swing / 3)
    }

    private func triggerKey(_ midi: Int, samples: Int, vel: Float) {
        var idx = keys.firstIndex { !$0.on } ?? 0
        if keys[idx].on {
            for v in 1..<keys.count where keys[v].t > keys[idx].t { idx = v }
        }
        nextPanLeft.toggle()
        keys[idx] = Key(on: true, f: mtof(midi), pan: nextPanLeft ? -0.35 : 0.35, gate: samples, vel: vel)
    }

    private func triggerPad(_ i: Int, vel: Float) {
        guard i >= 0 && i < Synth.padCount else { return }
        let style = pattern.style
        let base = sr * 60 / max(bpm, 30) / 4
        switch i {
        case 0: kick.trigger(vel)
        case 1: snare.trigger(vel, style, sr: sr)
        case 2:
            hat.trigger(vel * 0.6, decay: [45, 50, 65][style.rawValue], cutoff: style == .tripHop ? 6000 : 7500, sr: sr)
            openHat.choke()
        case 3: openHat.trigger(vel * 0.5, decay: [9, 12, 10][style.rawValue], cutoff: 7000, sr: sr)
        case 5: perc.trigger(vel * 0.6, sr: sr)
        case 12:
            for m in pattern.chords[lastBar] { triggerKey(m, samples: Int(base * 2), vel: 0.6 * vel) }
        case 13:
            line.trigger(mtof(pattern.bassRoots[lastBar] + 12), samples: Int(base * 3), vel: 0.9 * vel)
        default:
            let slot = Synth.padSlot[i]
            if slot >= 0 { padSounds[slot].trigger(vel, sr: sr) }
        }
        padHits[i] &+= 1
    }

    private func startLive(_ midi: Int) {
        let idx = liveNote.firstIndex(of: midi) ?? live.firstIndex { !$0.on } ?? 0
        live[idx] = Key(on: true, f: mtof(midi), attack: 0.03, gate: Int.max, vel: 0.85)
        liveNote[idx] = midi
    }

    private func stopLive(_ midi: Int) {
        for v in 0..<live.count where liveNote[v] == midi {
            live[v].gate = 0
            liveNote[v] = -1
        }
    }

    private func releaseAll() {
        bass.gate = 0
        line.gate = 0
        for v in 0..<keys.count { keys[v].gate = 0 }
    }
}
