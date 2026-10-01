import SwiftUI

/// One glass card per track, each with a vertical fader. Click a channel's name to
/// mute it.
struct FaderPanel: View {
    @Bindable var groove: Groove

    var body: some View {
        HStack(spacing: 12) {
            ForEach($groove.tracks) { $track in
                ChannelStrip(track: $track,
                             name: groove.trackName(track.id),
                             level: groove.levels[track.id],
                             accent: groove.style.accent)
                    .padding(.vertical, 14)
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular.tint(track.muted ? .clear : groove.style.accent.opacity(0.04 + 0.12 * groove.levels[track.id])),
                                 in: .rect(cornerRadius: 24))
            }
        }
    }
}

private struct ChannelStrip: View {
    @Binding var track: Track
    let name: String
    let level: Double
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Fader(value: $track.volume, level: track.muted ? 0 : level, accent: accent, name: name)
                .opacity(track.muted ? 0.4 : 1)

            VStack(spacing: 2) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(track.muted ? .secondary : .primary)
                Text("Muted")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(track.muted ? 1 : 0)       // keeps its space so the fader doesn't jump
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { track.muted.toggle() } }
            .help(track.muted ? "Click to unmute \(name)" : "Click to mute \(name)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(track.muted ? "\(name), muted" : name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: track.muted ? "Unmute" : "Mute") { track.muted.toggle() }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A hardware-style fader: a slot whose dim fill rises to the glass cap, with the live
/// level glowing inside that fill (so the meter never goes above the fader setting).
/// Drag anywhere on it; double-click to reset to 80%.
struct Fader: View {
    @Binding var value: Double
    let level: Double
    let accent: Color
    let name: String

    @State private var dragStart: Double?
    private let capHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.height - capHeight, 1)
            ZStack(alignment: .bottom) {
                let fill = capHeight / 2 + travel * value
                Capsule().fill(.black.opacity(0.35)).frame(width: 8)
                Capsule().fill(accent.opacity(0.35)).frame(width: 8, height: fill)
                Capsule()
                    .fill(accent)
                    .frame(width: 8, height: fill * min(level, 1))
                    .shadow(color: accent.opacity(0.8 * level), radius: 4)
                Color.clear
                    .frame(width: 34, height: capHeight)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 7))
                    .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 16, height: 2))
                    .offset(y: -travel * value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        value = min(max(dragStart! - g.translation.height / travel, 0), 1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { withAnimation(.smooth) { value = 0.8 } }
        }
        .frame(minHeight: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(value + 0.05, 1)
            case .decrement: value = max(value - 0.05, 0)
            @unknown default: break
            }
        }
    }
}
