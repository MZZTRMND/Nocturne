import SwiftUI

/// A rotary control on a glass cap. Drag up/down to change, double-click to reset.
struct Knob: View {
    let title: String
    @Binding var value: Double          // normalised 0...1
    let display: String
    var defaultValue: Double = 0.5

    @State private var dragStart: Double?
    @Environment(\.isEnabled) private var isEnabled

    private let size: CGFloat = 62

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * value)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Color.clear
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(9)
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 10)
                    .offset(y: -(size / 2 - 18))
                    .rotationEffect(.degrees(-135 + 270 * value))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        value = min(max(dragStart! - g.translation.height / 160, 0), 1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { withAnimation(.smooth) { value = defaultValue } }

            Text(display)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.85))
                .contentTransition(.numericText())
        }
        .frame(minWidth: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(value + 0.05, 1)
            case .decrement: value = max(value - 0.05, 0)
            @unknown default: break
            }
        }
    }
}
