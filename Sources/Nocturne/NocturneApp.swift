import AppKit
import SwiftUI

@main
struct NocturneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var groove = Groove()

    init() {
        let args = CommandLine.arguments
        if args.contains("--edit-test") {
            EditTest.run()
            exit(0)
        }
        if let i = args.firstIndex(of: "--prompt-test"), i + 1 < args.count {
            PromptTest.run(args[i + 1])
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-test") {
            RenderTest.run(into: i + 1 < args.count ? args[i + 1] : ".")
            exit(0)
        }
    }

    var body: some Scene {
        Window("Nocturne", id: "main") {
            ContentView(groove: groove)
                .task { await RecordTest.runIfRequested(groove) }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { groove.open() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { groove.save() }
                    .keyboardShortcut("s")
                Button("Save As…") { groove.save(as: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Playback") {
                Button(groove.isPlaying ? "Stop" : "Play") { groove.isPlaying.toggle() }
                    // Off while typing a prompt, or Space couldn't be typed.
                    .keyboardShortcut(groove.promptFocused ? nil : KeyboardShortcut(.space, modifiers: []))
                Button(groove.isRecording ? "Stop Recording" : "Record") { groove.toggleRecording() }
                    .keyboardShortcut("r")
                Divider()
                Picker("Style", selection: $groove.style) {
                    ForEach(Style.allCases) { style in
                        Text(style.title)
                            .tag(style)
                            .keyboardShortcut(KeyEquivalent(Character("\(style.rawValue + 1)")))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// `--snapshot <file.png>`: saves the window's contents once it has settled (debug aid).
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // `--snapshot-shortcuts` renders the help popover's content on its own.
            let content = args.contains("--snapshot-editor")
                ? AnyView(EditorPreview().padding(20).frame(width: 760).background(Color(white: 0.14)))
                : args.contains("--snapshot-shortcuts")
                ? AnyView(ShortcutsView().background(Color(white: 0.16)))
                : AnyView(ContentView(groove: {
                    let g = Groove()
                    g.manual = args.contains("--snapshot-manual")
                    return g
                }()))
            let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            NSApp.terminate(nil)
        }
    }
}

/// `NOCTURNE_RECORD_TEST="<seconds>|<file.wav>"`: records through the live engine (the
/// real tap path), saves straight to the file without a panel, then quits. Debug aid.
/// An environment variable rather than arguments: AppKit treats a bare path argument as
/// a document to open and then skips opening the main window.
@MainActor
enum RecordTest {
    static func runIfRequested(_ groove: Groove) async {
        guard let spec = ProcessInfo.processInfo.environment["NOCTURNE_RECORD_TEST"],
              let bar = spec.firstIndex(of: "|"),
              let seconds = Double(spec[..<bar]) else { return }
        let dest = URL(fileURLWithPath: String(spec[spec.index(after: bar)...]))
        // Optional: NOCTURNE_COMPOSE="<prompt>" runs the prompt first, through the real UI path.
        if let prompt = ProcessInfo.processInfo.environment["NOCTURNE_COMPOSE"] {
            groove.compose(prompt)
            while groove.isComposing { try? await Task.sleep(for: .milliseconds(100)) }
            let notes = dest.deletingPathExtension().appendingPathExtension("txt")
            let r = groove.recipe
            let summary = """
            note: \(groove.composeNote ?? "-")
            manual: \(groove.manual) · \(Int(groove.bpm)) bpm · \(groove.pattern.keyName) · drums \(r.drums?.title ?? "off") · bass \(r.bassSound?.bassSoundTitle ?? "off") · keys \(r.keys?.keysTitle ?? "off") · enters \(r.enter.map { $0 + 1 })
            """
            try? summary.write(to: notes, atomically: true, encoding: .utf8)
            groove.isPlaying = false
        }
        groove.startRecording()
        try? await Task.sleep(for: .seconds(seconds))
        groove.stopRecording(tail: 1, save: dest)
        try? await Task.sleep(for: .seconds(2))
        NSApp.terminate(nil)
    }
}

/// Both step-editor grids, for `--snapshot-editor`.
private struct EditorPreview: View {
    @State private var groove: Groove = {
        let g = Groove()
        g.manual = true
        return g
    }()
    @State private var octave = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DrumGrid(groove: groove, bar: 0).frame(height: 150)
            BassRoll(groove: groove, bar: 0, octave: $octave).frame(height: 280)
        }
        .tint(groove.style.accent)
    }
}

/// `--edit-test`: exercises hand edits, edit-preserving regeneration and project files.
@MainActor
enum EditTest {
    static func run() {
        func check(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name) }
        let g = Groove()
        g.manual = true
        let base = g.pattern.bassEditorBase
        let kickBefore = g.pattern.kick[1][5]
        g.edit { $0.toggle(.kick, bar: 1, step: 5) }
        check("kick toggles", g.pattern.kick[1][5] != kickBefore)
        g.edit { $0.line[0] = Array(repeating: nil, count: 16); $0.toggleBass(bar: 0, step: 3, midi: base + 3) }
        g.edit { $0.toggleBass(bar: 0, step: 7, midi: base + 7) }
        check("bass notes placed", g.pattern.line[0][3]?.midi == base + 3 && g.pattern.line[0][7]?.midi == base + 7)
        check("bass note rings until the next (max a beat)", g.pattern.line[0][3]?.len == 4 && g.pattern.line[0][7]?.len == 4)
        let rootBefore = g.pattern.bassRoots[2]
        g.edit { $0.setChord(bar: 2, root: 1, .maj7) }
        check("chord swapped", g.pattern.chordNames[2].hasSuffix("maj7") && g.pattern.bassRoots[2] != rootBefore)

        let edited = g.pattern
        g.manualRecipe.keys = .ambient
        check("changing keys keeps drum edit", g.pattern.kick == edited.kick)
        check("changing keys keeps bass edit", g.pattern.line == edited.line)
        check("changing keys keeps chord edit", g.pattern.chordNames == edited.chordNames)
        check("changing keys regenerates keys", g.pattern.keysSound == .ambient)

        g.manualRecipe.drums = .breakbeat
        check("new drum pattern replaces drums", g.pattern.kick != edited.kick)
        check("new drum pattern keeps bass edit", g.pattern.line == edited.line)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edit-test.nocturne")
        let data = try! JSONEncoder().encode(g.project)
        try! data.write(to: url)
        let g2 = Groove()
        g2.restore(try! JSONDecoder().decode(Groove.Project.self, from: Data(contentsOf: url)))
        check("project round-trips the pattern", g2.pattern == g.pattern)
        check("project round-trips settings", g2.manual && g2.manualRecipe == g.manualRecipe && g2.bpm == g.bpm)
        print("project file: \(data.count / 1024) KB")

        // Reset brings the preset back exactly as it was first loaded.
        let r = Groove()
        r.style = r.style == .industrial ? .dreamy : .industrial
        let fresh = r.pattern, d = r.style.defaults
        r.bpm = 150; r.tone = 0.1; r.volume = 0.3
        r.tracks[0].muted = true; r.tracks[2].volume = 0.2
        r.manual = true
        r.edit { $0.toggle(.snare, bar: 0, step: 3) }
        r.manualRecipe.keys = .synth
        r.resetPreset()
        check("reset restores the original pattern", r.pattern == fresh)
        check("reset restores default knobs", r.bpm == d.bpm && r.tone == d.tone && r.volume == 0.8)
        check("reset restores faders and mutes", r.tracks.allSatisfy { $0.volume == 0.8 && !$0.muted })
        check("reset leaves manual mode, keeping its setup", !r.manual && r.manualRecipe.keys == .synth)
    }
}

/// `--prompt-test "<text>"`: runs the prompt through the interpreter and prints the result.
enum PromptTest {
    static func run(_ prompt: String) {
        if let reason = AppleInterpreter.unavailableReason { print(reason); return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let spec = try await AppleInterpreter().interpret(prompt)
                let r = spec.recipe
                print("plan:", spec.plan)
                print("bpm \(spec.bpm) · \(r.keyName) · harmony \(r.harmony.harmonyTitle) · darkness \(spec.darkness) · distortion \(spec.distortion) · space \(spec.space)")
                print("drums \(r.drums?.title ?? "off") (\(r.kit.kitTitle) kit) · sub \(r.sub) · bass \(r.bassSound?.bassSoundTitle ?? "off") \(r.bassPattern.bassPatternTitle) · keys \(r.keys?.keysTitle ?? "off") · texture \(r.texture?.textureTitle ?? "off")")
                print("enters on bar (drums, sub, bass, keys, texture):", r.enter.map { $0 + 1 })
            } catch {
                print("error:", error)
            }
            done.signal()
        }
        done.wait()
    }
}

/// Offline render of every style to WAV, printing levels: a quick sanity check of the DSP
/// without needing to listen. `Nocturne --render-test <dir>`
enum RenderTest {
    static func run(into dir: String) {
        introReport()
        for style in Style.allCases {
            let (l, r) = render(style, gains: [0.8, 0.8, 0.8, 0.8, 0.8])
            let drums = render(style, gains: [0.8, 0, 0, 0, 0]).0
            let rest = render(style, gains: [0, 0.8, 0.8, 0.8, 0.8]).0
            let nans = l.contains { !$0.isFinite } || r.contains { !$0.isFinite }
            let name = "\(dir)/\(style.title).wav"
            writeWAV(name, l, r, sr: 44_100)
            print(String(format: "%-11@ mix peak %.2f rms %5.1f dB | drums rms %5.1f dB peak %.2f | rest rms %5.1f dB | >2kHz %4.1f%% | nan:%@",
                         style.title as NSString, peak(l), db(rms(l)), db(rms(drums)), peak(drums),
                         db(rms(rest)), brightness(l) * 100, nans ? "YES" : "no"))
            let parts = (0..<Synth.trackCount).map { i -> String in
                var g = [Float](repeating: 0, count: Synth.trackCount); g[i] = 0.8
                return String(format: "%@ %.1f", style.trackNames[i], db(rms(render(style, gains: g).0)))
            }
            print("            per track dB: " + parts.joined(separator: " · "))
        }
    }

    /// A mixed recipe with an intro build: prints the level of each of 8 bars.
    static func introReport() {
        var r = Recipe.preset(.industrial)
        r.drums = .breakbeat
        r.keys = .dreamy
        r.enter = [2, 1, 2, 0, 0]       // keys + texture, then sub, then drums and bass
        let synth = Synth(sampleRate: 44_100, pattern: Pattern.make(r, seed: 7))
        synth.bpm = 90; synth.grit = 0.4; synth.tone = 0.5
        synth.playing = true
        let barLen = Int(44_100 * 60 / Float(90) * 4)
        var line = "Intro (keys+texture → +sub at bar 2 → +drums & bass at bar 3), dB per bar:"
        for _ in 0..<8 {
            var l = [Float](repeating: 0, count: barLen), rr = l
            var at = 0
            while at < barLen {
                let n = min(512, barLen - at)
                l.withUnsafeMutableBufferPointer { lp in
                    rr.withUnsafeMutableBufferPointer { rp in synth.render(n, lp.baseAddress! + at, rp.baseAddress! + at) }
                }
                at += n
            }
            line += String(format: " %.1f", db(rms(l)))
        }
        print(line)
    }

    private static func render(_ style: Style, gains: [Float]) -> ([Float], [Float]) {
        let sr: Float = 44_100
        let synth = Synth(sampleRate: sr, pattern: Pattern.make(style, seed: 42))
        let d = style.defaults
        synth.bpm = Float(d.bpm); synth.swing = Float(d.swing)
        synth.tone = Float(d.tone); synth.grit = Float(d.grit)
        for i in 0..<Synth.trackCount { synth.gains[i] = gains[i] }
        synth.playing = true

        let frames = Int(sr * 60 / synth.bpm * 16)     // 4 bars
        var l = [Float](repeating: 0, count: frames), r = l
        var at = 0
        while at < frames {
            let n = min(512, frames - at)
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    synth.render(n, lp.baseAddress! + at, rp.baseAddress! + at)
                }
            }
            at += n
        }
        return (l, r)
    }

    /// Share of signal energy above ~2 kHz (one-pole high-pass): lower means darker.
    private static func brightness(_ x: [Float]) -> Float {
        let c = expf(-2 * .pi * 2000 / 44_100)
        var lp: Float = 0, hi: Float = 0, all: Float = 0
        for v in x { lp = (1 - c) * v + c * lp; let h = v - lp; hi += h * h; all += v * v }
        return all > 0 ? hi / all : 0
    }

    private static func peak(_ x: [Float]) -> Float { x.map(abs).max() ?? 0 }
    private static func rms(_ x: [Float]) -> Float { sqrt(x.map { $0 * $0 }.reduce(0, +) / Float(x.count)) }
    private static func db(_ x: Float) -> Float { 20 * log10(max(x, 1e-9)) }

    private static func writeWAV(_ path: String, _ l: [Float], _ r: [Float], sr: Int) {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(l.count * 4)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(2)
        u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for i in 0..<l.count {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, l[i])) * 32767)))
            u16(UInt16(bitPattern: Int16(max(-1, min(1, r[i])) * 32767)))
        }
        try? d.write(to: URL(fileURLWithPath: path))
    }
}
