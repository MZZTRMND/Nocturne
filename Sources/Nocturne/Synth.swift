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
        case .dreamy: f = 46 + 110 * expf(-t * 28); a = expf(-t * 5)
        case .synth: f = 45 + 70 * expf(-t * 25); a = expf(-t * 6)
        case .ambient: f = 38 + 30 * expf(-t * 10); a = expf(-t * 2.5)
        }
        ph += f * dt; wrap(&ph)
        let body = sinf(twoPi * ph) * a
        let click = t < 0.004 ? n * (1 - t / 0.004) * 0.45 : 0
        let out: Float
        switch s {
        case .tripHop: out = tanhf(body * 2.4) + click * 0.6
        case .industrial: out = tanhf(body * 4) * 0.8 + click
        case .dreamy: out = tanhf(body * 1.8) * 0.85 + click * 0.3     // round, soft beater
        case .synth: out = tanhf(body * 1.5) * 0.8 + click * 0.2     // muffled, felt-covered
        case .ambient: out = tanhf(body * 1.2) * 0.6                    // a far-off thud, no beater
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
        case .dreamy: bp.set(1500, k: 0.9, sr: sr)
        case .synth: bp.set(2500, k: 0.7, sr: sr)
        case .ambient: bp.set(900, k: 0.25, sr: sr)
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
        case .dreamy:       // soft, dusty snare
            ph += 190 * dt
            out = (sinf(twoPi * ph) * expf(-t * 25) * 0.5 + nz * expf(-t * 16) * 1.4) * 0.7
        case .synth:    // short, crunchy gated noise burst
            out = tanhf(nz * 3 * expf(-t * 20)) * 0.5
        case .ambient:  // creak: resonant noise that swells in and groans away
            out = nz * min(1, t / 0.15) * expf(-t * 3) * 0.8
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
        guard t < (s == .ambient ? 4 : 1.5) else { return 0 }
        var out: Float
        if s == .ambient {   // metal clang: inharmonic FM with a long ring
            pc += 220 * dt; pm += 220 * 2.76 * dt
            wrap(&pc); wrap(&pm)
            out = tanhf(sinf(twoPi * pc + 4 * expf(-t * 2) * sinf(twoPi * pm)) * expf(-t * 1.5)) * 0.5
        } else if s == .synth {     // digital glitch blip
            pc += 1800 * dt; wrap(&pc)
            out = (pc < 0.5 ? 1 : -1) * expf(-t * 90) * 0.4
        } else if s == .industrial {
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
/// plucked arpeggio (dreamy). A note that arrives while the previous one is still held
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
        case .dreamy:       // triangle/saw blend, gently filtered, decaying like a pluck
            lp.set(500 + 1800 * expf(-t * 7), k: 0.9, sr: sr)
            out = lp.tick(0.6 * (4 * abs(ph - 0.5) - 1) + 0.4 * (2 * ph - 1)).lp * 0.6 * expf(-t * 2.5)
        case .ambient:  // low drone that swells in, its filter breathing slowly
            lp.set(150 + 250 * (0.5 + 0.5 * sinf(t * 0.6)), k: 0.5, sr: sr)
            out = lp.tick(2 * ph - 1).lp * 0.8 * min(1, t / 1.5)
        case .synth:    // staccato analog pulse: saw + square through a resonant lowpass
            lp.set(300 + 1500 * expf(-t * 12), k: 0.35, sr: sr)
            out = tanhf(lp.tick(0.5 * (2 * ph - 1) + 0.5 * (ph < 0.5 ? 1 : -1)).lp * 1.8) * 0.45
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
        if gate > 0 { gate -= 1; relEnv = 1 } else { rt += dt; relEnv = expf(-rt * [7, 2.5, 1.6, 4, 1][s.rawValue]) }
        let amp, out: Float
        switch s {
        case .industrial:   // slow detuned saw pad with a sub-octave sine
            pc += f * 1.006 * dt; pm += f * 0.994 * dt; p2 += f * 0.5 * dt
            wrap(&pc); wrap(&pm); wrap(&p2)
            amp = min(1, t / attack)
            out = ((2 * pc - 1) + (2 * pm - 1)) * 0.5 + sinf(twoPi * p2) * 0.4
        case .dreamy:       // warm, wide pad: detuned saws over a soft triangle
            let pf = f * pitch
            pc += pf * 1.005 * dt; pm += pf * 0.995 * dt; p2 += pf * dt
            wrap(&pc); wrap(&pm); wrap(&p2)
            amp = min(1, t / attack)
            out = ((2 * pc - 1) + (2 * pm - 1)) * 0.35 + (4 * abs(p2 - 0.5) - 1) * 0.5
        case .ambient:  // eerie pad: two slightly detuned sines beating, a faint bell on top
            let pf = f * pitch
            pc += pf * 1.003 * dt; pm += pf * 0.997 * dt; p2 += pf * 3 * dt
            wrap(&pc); wrap(&pm); wrap(&p2)
            amp = min(1, t / (attack * 2))
            out = (sinf(twoPi * pc) + sinf(twoPi * pm)) * 0.5 + sinf(twoPi * p2) * 0.15 * expf(-t * 0.5)
        case .synth:    // felt piano: three partials, the upper ones dying away first
            pc += f * dt; p2 += 2 * f * dt; pm += 3 * f * dt
            wrap(&pc); wrap(&p2); wrap(&pm)
            out = sinf(twoPi * pc) + sinf(twoPi * p2) * 0.5 * expf(-t * 3) + sinf(twoPi * pm) * 0.25 * expf(-t * 6)
            amp = min(1, t / 0.002) * expf(-t * 1.1)
        case .tripHop:      // FM electric piano
            pc += f * dt; pm += f * dt
            wrap(&pc); wrap(&pm)
            let idx = 0.8 * expf(-t * 4) + 0.1
            out = sinf(twoPi * pc + idx * sinf(twoPi * pm))
            amp = min(1, t / 0.003) * expf(-t * 0.7)
        }
        t += dt
        let a = amp * relEnv * vel
        if relEnv < 0.0005 || ((s == .tripHop || s == .synth) && t > 0.1 && a < 0.00005) { on = false }
        return out * a
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
    /// Set from the main thread to jump back to bar 1 (e.g. to hear a new intro).
    private var restartRequested = false
    func restart() { restartRequested = true }
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

    private var wasPlaying = false
    private var globalStep = 0
    private var samplesToNext: Float = 0
    private var noise = Noise()
    private var smoothGains = [Float](repeating: 0.8, count: Synth.trackCount)
    private var smoothMaster: Float = 0.8

    private var kick = Kick(), snare = Snare(), hat = Hat(), openHat = Hat(), perc = Perc()
    private var bass = Bass()
    private var line = LineBass()
    private var keys = [Key](repeating: Key(), count: 12)
    private var live = [Key](repeating: Key(), count: 10)
    private var liveNote = [Int](repeating: -1, count: 10)
    private var nextPanLeft = true
    private var kickFollow: Float = 0
    /// Bars since playback started (not wrapped), for the intro arrangement.
    private var songBar = 0
    private var texGain: Float = 1

    private var keysL = SVF(), keysR = SVF(), toneL = SVF(), toneR = SVF()
    private var hissLP = SVF(), droneBP = SVF(), rumbleLP = SVF(), airBP = SVF()
    private var windA = SVF(), windB = SVF()
    private var windPh: Float = 0, geigerBurst: Float = 0, geigerClick: Float = 0
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
        hissLP.set(3200, k: 1, sr: sr)
        rumbleLP.set(160, k: 0.9, sr: sr)
    }

    deinit {
        gains.deallocate()
        meters.deallocate()
    }

    func setPattern(_ p: Pattern) {
        lock.lock()
        pending = p
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
            lock.unlock()
        }

        let isOn = playing
        if isOn && !wasPlaying { globalStep = 0; samplesToNext = 0 }
        if !isOn && wasPlaying { releaseAll(); uiStep = -1 }
        if restartRequested {
            restartRequested = false
            if isOn { globalStep = 0; samplesToNext = 0; songBar = 0; releaseAll() }
        }
        wasPlaying = isOn

        // Each part can use a different style's sound (manual mode); `main` sets the
        // overall balance.
        let main = pattern.style, kitS = pattern.kit, bassS = pattern.bassSound
        let keysS = pattern.keysSound, texS = pattern.textureSound
        let texTarget: Float = pattern.hasTexture && (!isOn || songBar >= pattern.enter[4]) ? 1 : 0
        let cutoff = 250 * powf(80, min(max(tone, 0), 1))
        toneL.set(cutoff, k: 1.1, sr: sr)
        toneR.set(cutoff, k: 1.1, sr: sr)
        let sweep = 0.5 + 0.5 * sinf(twoPi * lfoSlow)
        switch keysS {
        case .tripHop: keysL.set(1400, k: 0.9, sr: sr)
        case .industrial: keysL.set(300 + 1800 * sweep, k: 0.3, sr: sr)
        case .dreamy: keysL.set(1100 + 700 * sweep, k: 0.8, sr: sr)
        case .synth: keysL.set(2400, k: 0.9, sr: sr)
        case .ambient: keysL.set(900 + 600 * sweep, k: 0.6, sr: sr)
        }
        keysR.g = keysL.g; keysR.k = keysL.k
        droneBP.set(220 + 900 * sweep, k: 0.15, sr: sr)
        airBP.set(3000 + 4000 * sweep, k: 0.8, sr: sr)
        windA.set(300 + 900 * sweep, k: 0.25, sr: sr)
        windB.set(1200 + 1500 * (1 - sweep), k: 0.35, sr: sr)
        let drive = 1 + grit * 12

        for i in 0..<n {
            if isOn {
                if samplesToNext <= 0 { fireStep() }
                samplesToNext -= 1
            }
            for j in 0..<Synth.trackCount { smoothGains[j] += (gains[j] - smoothGains[j]) * 0.002 }

            // Drums
            let k = kick.next(kitS, dt, noise.next()) * 1.35
            let sn = snare.next(kitS, dt, noise.next()) * 0.9
            let hh = hat.next(dt, noise.next()) * 0.4
            let oh = openHat.next(dt, noise.next()) * 0.32
            let pc = perc.next(kitS, dt, noise.next()) * 0.45
            let dScale: Float = [1, 1, 0.7, 0.8, 0.8][kitS.rawValue]   // ambient styles: drums sit behind
            let dL = (k + sn + hh * 0.7 + oh * 0.7 + pc * 1.2) * smoothGains[0] * dScale
            let dR = (k + sn + hh * 1.3 + oh * 1.3 + pc * 0.8) * smoothGains[0] * dScale

            // Everything else ducks under the kick, so it punches through the mix.
            kickFollow = max(abs(k) * smoothGains[0], kickFollow * 0.9993)
            let duck = 1 - [0.4, 0.4, 0.2, 0.25, 0.1][kitS.rawValue] * min(kickFollow, 1)

            // Tape wow and flutter: a slow, slightly seasick warble on dreamy-sounding parts.
            wowPh += 0.35 * dt; wrap(&wowPh)
            flutterPh += 6 * dt; wrap(&flutterPh)
            let wobble = 1 + 0.0035 * sinf(twoPi * wowPh) + 0.0008 * sinf(twoPi * flutterPh)
            let keysPitch: Float = keysS == .dreamy || keysS == .ambient ? wobble : 1
            let linePitch: Float = bassS == .dreamy || bassS == .ambient ? wobble : 1

            // Sub + bass line
            let b = bass.next(dt, atk: atk, rel: rel) * 0.42 * [1, 1, 1, 0.5, 0.48][main.rawValue] * smoothGains[1] * duck
            let ln = line.next(bassS, dt, sr: sr, atk: atk, rel: rel, pitch: linePitch) * 0.4 * [1, 1, 2.7, 1.8, 1.0][bassS.rawValue] * smoothGains[2] * duck

            // Keys: the pattern's chords plus anything played live
            var kL: Float = 0, kR: Float = 0
            for v in 0..<keys.count where keys[v].on {
                let s = keys[v].next(keysS, dt, pitch: keysPitch) * 0.11
                kL += s * (1 - keys[v].pan)
                kR += s * (1 + keys[v].pan)
            }
            for v in 0..<live.count where live[v].on {
                let s = live[v].next(keysS, dt, pitch: keysPitch) * 0.16
                kL += s
                kR += s
            }
            kL = keysL.tick(kL).lp
            kR = keysR.tick(kR).lp
            if keysS == .tripHop {
                let tr = sinf(twoPi * lfoTrem)
                kL *= 1 - 0.25 * (0.5 + 0.5 * tr)
                kR *= 1 - 0.25 * (0.5 - 0.5 * tr)
            }
            let kScale: Float = [2.9, 1, 2.8, 3.2, 4.0][keysS.rawValue]
            kL *= smoothGains[3] * duck * kScale
            kR *= smoothGains[3] * duck * kScale

            // Texture
            var tx: Float
            switch texS {
            case .industrial:
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * dt; wrap(&dronePh)
                tx = droneBP.tick(noise.next()).bp * 0.06 + rumbleLP.tick(2 * dronePh - 1).lp * 0.22
            case .synth:    // static and crackle over a saturated drone on the root
                if noise.next() > 0.9995 { crackle = 0.2 + 0.2 * noise.next() }
                crackle *= 0.6
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * dt; wrap(&dronePh)
                tx = tanhf(rumbleLP.tick(2 * dronePh - 1).lp * 2) * 0.1 + droneBP.tick(noise.next()).bp * 0.02
                    + crackle * noise.next()
            case .ambient:  // wind through ruins, Geiger-counter crackle in bursts, a low hum
                windPh += 0.023 * dt; wrap(&windPh)
                let gust = 0.4 + 0.6 * (0.5 + 0.5 * sinf(twoPi * windPh))
                let wind = (windA.tick(noise.next()).bp * 0.05 + windB.tick(noise.next()).bp * 0.03) * gust
                if noise.next() > 0.99995 { geigerBurst = 1 }
                geigerBurst *= 0.99997
                if noise.next() > 0.9997 - 0.004 * geigerBurst { geigerClick = 0.25 + 0.2 * noise.next() }
                geigerClick *= 0.4
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * dt; wrap(&dronePh)
                tx = wind + geigerClick + rumbleLP.tick(2 * dronePh - 1).lp * 0.08
            case .dreamy:   // tape hiss with a little air on top
                tx = hissLP.tick(noise.next()).lp * 0.025 + airBP.tick(noise.next()).bp * 0.02
            case .tripHop:  // vinyl crackle over a low, slowly breathing drone on the root
                if noise.next() > 0.9992 { crackle = 0.3 + 0.3 * noise.next() }
                crackle *= 0.55
                droneF += (droneTarget - droneF) * 0.0005
                dronePh += droneF * 2 * dt; wrap(&dronePh)
                let drone = rumbleLP.tick(2 * dronePh - 1).lp * 0.12 + droneBP.tick(noise.next()).bp * 0.025
                tx = crackle * noise.next() + hissLP.tick(noise.next()).lp * 0.02 + drone
            }
            texGain += (texTarget - texGain) * 0.0005      // texture fades in when it enters
            tx *= smoothGains[4] * [1, 1, 1, 0.5, 1.8][texS.rawValue] * texGain

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
        songBar = globalStep / 16
        let bar = songBar % 4, s = globalStep % 16
        let kitS = pattern.kit
        // Intro arrangement: a part stays silent until its entry bar.
        let drumsIn = songBar >= pattern.enter[0], subIn = songBar >= pattern.enter[1]
        let bassIn = songBar >= pattern.enter[2], keysIn = songBar >= pattern.enter[3]
        let base = sr * 60 / max(bpm, 30) / 4
        let human = 0.92 + 0.08 * noise.next()

        if drumsIn { fireDrums(bar, s, kitS, human) }
        if subIn, let h = pattern.bass[bar][s] {
            bass.trigger(mtof(h.midi), samples: Int(Float(h.len) * base * 0.92), vel: h.vel)
        }
        if bassIn, let h = pattern.line[bar][s] {
            line.trigger(mtof(h.midi), samples: Int(Float(h.len) * base * 0.92), vel: h.vel)
        }
        if keysIn, let h = pattern.melody[bar][s] {
            triggerKey(h.midi, samples: Int(Float(h.len) * base * 0.95), vel: h.vel)
        }
        if keysIn, let h = pattern.comp[bar][s] {
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

    private func fireDrums(_ bar: Int, _ s: Int, _ kitS: Style, _ human: Float) {
        if pattern.kick[bar][s] > 0 { kick.trigger(pattern.kick[bar][s] * human) }
        if pattern.snare[bar][s] > 0 { snare.trigger(pattern.snare[bar][s] * human, kitS, sr: sr) }
        if pattern.hat[bar][s] > 0 {
            hat.trigger(pattern.hat[bar][s] * human, decay: [45, 50, 65, 80, 120][kitS.rawValue],
                        cutoff: kitS == .tripHop ? 6000 : 7500, sr: sr)
            openHat.choke()
        }
        if pattern.open[bar][s] > 0 {
            openHat.trigger(pattern.open[bar][s] * human, decay: [9, 12, 10, 14, 6][kitS.rawValue], cutoff: 7000, sr: sr)
        }
        if pattern.perc[bar][s] > 0 { perc.trigger(pattern.perc[bar][s] * human, sr: sr) }
    }

    private func triggerKey(_ midi: Int, samples: Int, vel: Float) {
        var idx = keys.firstIndex { !$0.on } ?? 0
        if keys[idx].on {
            for v in 1..<keys.count where keys[v].t > keys[idx].t { idx = v }
        }
        nextPanLeft.toggle()
        keys[idx] = Key(on: true, f: mtof(midi), pan: nextPanLeft ? -0.35 : 0.35, gate: samples, vel: vel)
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
