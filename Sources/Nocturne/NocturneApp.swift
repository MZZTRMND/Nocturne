import AppKit
import SwiftUI

@main
struct NocturneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var groove = Groove()

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-test") {
            RenderTest.run(into: i + 1 < args.count ? args[i + 1] : ".")
            exit(0)
        }
    }

    var body: some Scene {
        Window("Nocturne", id: "main") {
            ContentView(groove: groove)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Playback") {
                Button(groove.isPlaying ? "Stop" : "Play") { groove.isPlaying.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
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
            let renderer = ImageRenderer(content: ContentView(groove: Groove()).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            NSApp.terminate(nil)
        }
    }
}

/// Offline render of every style to WAV, printing levels: a quick sanity check of the DSP
/// without needing to listen. `Nocturne --render-test <dir>`
enum RenderTest {
    static func run(into dir: String) {
        for style in Style.allCases {
            let (l, r) = render(style, gains: [0.8, 0.8, 0.8, 0.8, 0.8])
            let drums = render(style, gains: [0.8, 0, 0, 0, 0]).0
            let rest = render(style, gains: [0, 0.8, 0.8, 0.8, 0.8]).0
            let nans = l.contains { !$0.isFinite } || r.contains { !$0.isFinite }
            let name = "\(dir)/\(style.title).wav"
            writeWAV(name, l, r, sr: 44_100)
            print(String(format: "%-11@ mix peak %.2f rms %5.1f dB | drums rms %5.1f dB peak %.2f | rest rms %5.1f dB | nan:%@",
                         style.title as NSString, peak(l), db(rms(l)), db(rms(drums)), peak(drums),
                         db(rms(rest)), nans ? "YES" : "no"))
        }
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
