import SwiftUI

/// Popover listing the app's shortcuts and how the computer keyboard maps to the piano.
struct ShortcutsView: View {
    private let shortcuts: [(keys: [String], action: String)] = [
        (["Space"], "Play / Stop"),
        (["⌘", "R"], "Record / stop recording"),
        (["⌘", "1"], "Trip-Hop"),
        (["⌘", "2"], "Industrial"),
        (["⌘", "3"], "Techno"),
        (["⌘", "/"], "Show this help"),
    ]

    // Computer keys → notes, laid out like the keyboard itself (C4–E5).
    private let whites: [(key: String, note: String)] = [
        ("A", "C"), ("S", "D"), ("D", "E"), ("F", "F"), ("G", "G"),
        ("H", "A"), ("J", "B"), ("K", "C"), ("L", "D"), (";", "E"),
    ]
    /// Black keys by the index of the white key they sit after; nil where there's a gap.
    private let blacks: [(key: String, note: String)?] = [
        ("W", "C♯"), ("E", "D♯"), nil, ("T", "F♯"), ("Y", "G♯"), ("U", "A♯"), nil,
        ("O", "C♯"), ("P", "D♯"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Shortcuts") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    ForEach(shortcuts.indices, id: \.self) { i in
                        GridRow {
                            HStack(spacing: 3) { ForEach(shortcuts[i].keys, id: \.self) { KeyCap($0) } }
                            Text(shortcuts[i].action)
                        }
                    }
                }
            }

            section("Play the piano") {
                VStack(alignment: .leading, spacing: 6) {
                    // Black keys, offset half a key so they sit between the white ones.
                    HStack(spacing: 4) {
                        ForEach(blacks.indices, id: \.self) { i in
                            if let b = blacks[i] { NoteKey(b.key, b.note, dark: true) } else { Color.clear.frame(width: 30, height: 1) }
                        }
                    }
                    .padding(.leading, 17)
                    HStack(spacing: 4) {
                        ForEach(whites.indices, id: \.self) { i in NoteKey(whites[i].key, whites[i].note, dark: false) }
                    }
                }
                Text("Plays C4 – E5 with the current keys sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            section("Knobs") {
                Text("Drag up or down to turn. Double-click to reset.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(20)
        .frame(width: 380)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold).monospaced())
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.12)))
    }
}

private struct NoteKey: View {
    let key: String, note: String, dark: Bool
    init(_ key: String, _ note: String, dark: Bool) { self.key = key; self.note = note; self.dark = dark }

    var body: some View {
        VStack(spacing: 1) {
            Text(key).font(.caption.weight(.bold).monospaced())
            Text(note).font(.system(size: 9)).opacity(0.7)
        }
        .foregroundStyle(dark ? .white : .black)
        .frame(width: 30, height: 34)
        .background(dark ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(Color.white.opacity(0.9)),
                    in: .rect(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(dark ? 0.15 : 0)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key) plays \(note)")
    }
}
