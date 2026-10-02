import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case keys = "Keys", drums = "Drums", bass = "Bass"
    var id: String { rawValue }
}

/// Click-to-toggle grid of drum hits for one bar.
struct DrumGrid: View {
    let groove: Groove
    let bar: Int

    var body: some View {
        VStack(spacing: 6) {
            ForEach(DrumLane.allCases) { lane in
                HStack(spacing: 10) {
                    Text(lane.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)
                    StepRow(playhead: playhead, accent: groove.style.accent,
                            value: { groove.pattern[keyPath: lane.path][bar][$0] },
                            tap: { s in groove.edit { $0.toggle(lane, bar: bar, step: s) } })
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(lane.title), bar \(bar + 1)")
            }
        }
    }

    private var playhead: Int { groove.isPlaying && groove.bar == bar ? groove.step : -1 }
}

/// One octave (shiftable) of the bass line for one bar: click to place or remove a note.
struct BassRoll: View {
    let groove: Groove
    let bar: Int
    @Binding var octave: Int

    private static let minorScale: Set<Int> = [0, 2, 3, 5, 7, 8, 10]

    var body: some View {
        let base = groove.pattern.bassEditorBase + 12 * octave
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 4) {
                Button { octave = min(octave + 1, 1) } label: { Image(systemName: "chevron.up") }
                    .disabled(octave >= 1)
                    .help("Octave up")
                Text(octave == 0 ? "Oct" : octave > 0 ? "+1" : "−1")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { octave = max(octave - 1, -1) } label: { Image(systemName: "chevron.down") }
                    .disabled(octave <= -1)
                    .help("Octave down")
            }
            .buttonStyle(.borderless)
            .frame(width: 28)

            VStack(spacing: 2) {
                ForEach((0...12).reversed(), id: \.self) { i in
                    let midi = base + i
                    let inScale = Self.minorScale.contains(((midi - groove.pattern.keyRoot) % 12 + 12) % 12)
                    HStack(spacing: 10) {
                        Text(noteNames[midi % 12] + "\(midi / 12 - 1)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(inScale ? .secondary : .tertiary)
                            .frame(width: 28, alignment: .leading)
                        StepRow(playhead: playhead, accent: groove.style.accent, dim: !inScale,
                                value: { cell(midi, $0) },
                                tap: { s in groove.edit { $0.toggleBass(bar: bar, step: s, midi: midi) } })
                    }
                }
            }
        }
    }

    /// 1 at a note's start, 0.35 where it is still ringing, 0 elsewhere.
    private func cell(_ midi: Int, _ step: Int) -> Float {
        let line = groove.pattern.line[bar]
        if line[step]?.midi == midi { return 1 }
        for s in stride(from: step - 1, through: max(step - 4, 0), by: -1) {
            if let h = line[s] { return h.midi == midi && s + h.len > step ? 0.35 : 0 }
        }
        return 0
    }

    private var playhead: Int { groove.isPlaying && groove.bar == bar ? groove.step : -1 }
}

/// 16 cells in four groups of four.
private struct StepRow: View {
    let playhead: Int
    let accent: Color
    var dim = false
    let value: (Int) -> Float
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { s in
                let v = value(s)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(v > 0 ? AnyShapeStyle(accent.opacity(Double(0.35 + 0.65 * min(v, 1))))
                                : AnyShapeStyle(Color.white.opacity(dim ? 0.04 : (s % 4 == 0 ? 0.12 : 0.08))))
                    .overlay {
                        if s == playhead {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, s % 4 == 0 && s > 0 ? 6 : 0)
                    .contentShape(.rect)
                    .onTapGesture { tap(s) }
                    .accessibilityElement()
                    .accessibilityLabel("Step \(s + 1)")
                    .accessibilityValue(v >= 1 ? "on" : v > 0 ? "held" : "off")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { tap(s) }
            }
        }
    }
}
