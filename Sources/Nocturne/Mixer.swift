import SwiftUI

/// Channel strips with vertical faders, one per track. Click a channel's name or icon
/// to mute it.
struct FaderPanel: View {
    @Bindable var groove: Groove

    var body: some View {
        HStack(spacing: 4) {
            ForEach($groove.tracks) { $track in
                ChannelStrip(track: $track,
                             name: groove.trackName(track.id),
                             level: groove.levels[track.id],
                             accent: groove.style.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
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

            VStack(spacing: 4) {
                Image(systemName: track.muted ? "speaker.slash.fill" : track.icon)
                    .font(.body)
                    .foregroundStyle(track.muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .opacity(track.muted ? 1 : 0.5 + 0.5 * level)
                    .frame(height: 18)
                    .contentTransition(.symbolEffect(.replace))
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(track.muted ? .secondary : .primary)
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
        .frame(minWidth: 58)
    }
}

/// A hardware-style fader: slot, coloured fill up to a glass cap, and a live level meter
/// beside it. Drag anywhere on it; double-click to reset to 80%.
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
                Capsule().fill(.black.opacity(0.35)).frame(width: 6)
                Capsule().fill(accent).frame(width: 6, height: capHeight / 2 + travel * value)
                // Level meter to the right of the slot.
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: 3, height: geo.size.height * min(level, 1))
                    .offset(x: 13)
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
        .frame(minHeight: 120)
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
