import SwiftUI

/// Playable keyboard, C3–E5. The current chord's notes are lit in the accent colour.
/// Play it by clicking, or from the computer keyboard (A W S E D F T G Y H U J K O L P ;
/// covers C4–E5).
struct PianoPanel: View {
    let groove: Groove

    @State private var pressed: Set<Int> = []
    @FocusState private var focused: Bool

    private static let keymap: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8,
        "h": 9, "u": 10, "j": 11, "k": 12, "o": 13, "l": 14, "p": 15, ";": 16,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(groove.trackName(3)).font(.headline)
                Text("Click or play A – ; on your keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            PianoKeyboard(chordNotes: groove.chordNotes,
                          pressed: pressed,
                          accent: groove.style.accent,
                          down: press,
                          up: release)
                .frame(minHeight: 300, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { pressed.forEach(release) }      // never leave a note hanging
        }
        .onKeyPress(phases: [.down, .up]) { key in
            guard key.modifiers.subtracting(.shift).isEmpty,
                  let c = key.characters.lowercased().first,
                  let offset = Self.keymap[c] else { return .ignored }
            let midi = 60 + offset
            if key.phase == .down { press(midi) } else { release(midi) }
            return .handled
        }
    }

    private func press(_ midi: Int) {
        focused = true      // clicking a key takes typing focus back from the prompt field
        guard !pressed.contains(midi) else { return }
        pressed.insert(midi)
        groove.noteOn(midi)
    }

    private func release(_ midi: Int) {
        guard pressed.contains(midi) else { return }
        pressed.remove(midi)
        groove.noteOff(midi)
    }
}

struct PianoKeyboard: View {
    let chordNotes: Set<Int>
    let pressed: Set<Int>
    let accent: Color
    let down: (Int) -> Void
    let up: (Int) -> Void

    private let low = 48, high = 76
    private let gap: CGFloat = 4
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    private func isBlack(_ m: Int) -> Bool { [1, 3, 6, 8, 10].contains(m % 12) }

    var body: some View {
        GeometryReader { geo in
            let whites = (low...high).filter { !isBlack($0) }
            let w = (geo.size.width - gap * CGFloat(whites.count - 1)) / CGFloat(whites.count)
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { i, m in
                    whiteKey(m)
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(i) * (w + gap))
                }
                ForEach((low...high).filter(isBlack), id: \.self) { m in
                    let left = whites.firstIndex(of: m - 1) ?? 0
                    blackKey(m)
                        .frame(width: w * 0.62, height: h * 0.6)
                        .offset(x: CGFloat(left + 1) * (w + gap) - gap / 2 - w * 0.31)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Piano keyboard")
    }

    private func whiteKey(_ m: Int) -> some View {
        let isDown = pressed.contains(m), inChord = chordNotes.contains(m)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(inChord || isDown ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(0.9)))
            .brightness(isDown ? 0.18 : 0)
            .overlay(alignment: .bottom) {
                Text(Self.names[m % 12] + "\(m / 12 - 1)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.black.opacity(0.45))
                    .padding(.bottom, 8)
            }
            .shadow(color: .black.opacity(isDown ? 0.1 : 0.35), radius: isDown ? 1 : 3, y: isDown ? 1 : 3)
            .scaleEffect(isDown ? 0.97 : 1, anchor: .top)
            .gesture(keyGesture(m))
            .accessibilityElement()
            .accessibilityLabel(Self.names[m % 12] + "\(m / 12 - 1)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap(m) }
    }

    private func blackKey(_ m: Int) -> some View {
        let isDown = pressed.contains(m), inChord = chordNotes.contains(m)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(inChord || isDown
                  ? AnyShapeStyle(accent)
                  : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                                                 startPoint: .top, endPoint: .bottom)))
            .brightness(isDown ? 0.18 : 0)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 3)
            .scaleEffect(isDown ? 0.96 : 1, anchor: .top)
            .gesture(keyGesture(m))
            .accessibilityElement()
            .accessibilityLabel(Self.names[m % 12] + "\(m / 12 - 1)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap(m) }
    }

    private func tap(_ m: Int) {
        down(m)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { up(m) }
    }

    private func keyGesture(_ m: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in down(m) }
            .onEnded { _ in up(m) }
    }
}
