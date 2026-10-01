import AppKit
import SwiftUI

/// 4×4 drum pads, laid out like a hardware pad controller: pad 1 bottom-left, pad 16
/// top-right. Pads flash when clicked, when their key is pressed, and when the
/// sequencer plays their drum.
struct PadPanel: View {
    let groove: Groove

    @State private var monitor: Any?

    /// Keys per pad, indexed like `Synth.padNames`. Rows from the bottom: Z–V, B–comma,
    /// 5–8, 1–4, so the top keyboard row plays the top pads. None overlap the piano keys.
    static let keys: [Character] = ["z", "x", "c", "v", "b", "n", "m", ",",
                                    "5", "6", "7", "8", "1", "2", "3", "4"]

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.27, blue: 0.33), Color(red: 1.0, green: 0.62, blue: 0.2),
        Color(red: 0.75, green: 0.4, blue: 1.0), Color(red: 0.3, green: 0.75, blue: 1.0),
        Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 1.0, green: 0.78, blue: 0.25),
        Color(red: 1.0, green: 0.35, blue: 0.75), Color(red: 1.0, green: 0.4, blue: 0.7),
        Color(red: 0.6, green: 0.45, blue: 1.0), Color(red: 0.55, green: 0.45, blue: 1.0),
        Color(red: 0.75, green: 0.4, blue: 1.0), Color(red: 0.35, green: 0.55, blue: 1.0),
        Color(red: 1.0, green: 0.3, blue: 0.4), Color(red: 1.0, green: 0.3, blue: 0.4),
        Color(red: 1.0, green: 0.35, blue: 0.45), Color(red: 1.0, green: 0.3, blue: 0.4),
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach((0..<4).reversed(), id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { col in
                        let i = row * 4 + col
                        Pad(name: Synth.padNames[i],
                            key: Self.keys[i] == "," ? "," : String(Self.keys[i]).uppercased(),
                            color: Self.colors[i],
                            hits: groove.padHits[i]) { groove.hitPad(i) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .onAppear(perform: installKeys)
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    /// App-wide key handling, so pads play whatever has focus. Panels (save sheet,
    /// popovers) and anything with ⌘/⌃/⌥ are left alone.
    private func installKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat, !(event.window is NSPanel),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let c = event.charactersIgnoringModifiers?.lowercased().first,
                  let i = PadPanel.keys.firstIndex(of: c) else { return event }
            groove.hitPad(i)
            return nil
        }
    }
}

private struct Pad: View {
    let name: String
    let key: String
    let color: Color
    let hits: Int
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: hits) { glow in
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.9 * glow))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.75 + 0.25 * glow), lineWidth: 2)
                }
                .shadow(color: color.opacity(0.3 + 0.6 * glow), radius: 5 + 10 * glow)
                .overlay(alignment: .topLeading) {
                    Text(name.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(7)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(key)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(7)
                }
                .scaleEffect(1 - 0.04 * glow)
        } keyframes: { _ in
            LinearKeyframe(1, duration: 0.02)
            CubicKeyframe(0, duration: 0.35)
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; action() } }
                .onEnded { _ in pressed = false }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) pad")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
