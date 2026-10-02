import SwiftUI

/// Prompt field: describe the music and the on-device model sets up manual mode.
struct ComposeBar: View {
    @Bindable var groove: Groove
    @State private var prompt = ""
    @FocusState private var focused: Bool

    private var unavailable: String? { AppleInterpreter.unavailableReason }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: groove.isComposing)

                // Fixed colours: the glass adapts "secondary" text to the animated backdrop
                // behind it, which made the placeholder flicker with the beat.
                TextField("Prompt", text: $prompt,
                          prompt: Text("Describe the music — mood, tempo, artists, how it should start…")
                              .foregroundStyle(Color.white.opacity(0.42)),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1...3)
                    .focused($focused)
                    .onSubmit { groove.compose(prompt) }
                    .disabled(groove.isComposing)

                if groove.isComposing {
                    ProgressView().controlSize(.small)
                }

                Button("Create") { groove.compose(prompt) }
                    .buttonStyle(.glassProminent)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || groove.isComposing || unavailable != nil)
                    .help(unavailable ?? "Turn the description into a groove (Return)")
            }

            if let note = groove.composeNote ?? unavailable {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(groove.composeFailed || groove.composeNote == nil
                                     ? Color.orange : Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .onChange(of: focused) { _, isFocused in groove.promptFocused = isFocused }
    }
}

// MARK: - Manual controls

/// Small native pop-up menus for one mixer channel in manual mode.
struct ChannelControls: View {
    @Bindable var groove: Groove
    let track: Int

    var body: some View {
        VStack(spacing: 6) {
            switch track {
            case 0:
                menu("Pattern", selection: $groove.manualRecipe.drums) {
                    Text("No drums").tag(DrumGroove?.none)
                    ForEach(DrumGroove.allCases) { Text($0.title).tag(DrumGroove?.some($0)) }
                }
                menu("Kit", selection: $groove.manualRecipe.kit) {
                    ForEach(Style.allCases) { Text($0.kitTitle).tag($0) }
                }
            case 1:
                menu("Sub", selection: $groove.manualRecipe.sub) {
                    Text("Sub on").tag(true)
                    Text("Sub off").tag(false)
                }
            case 2:
                menu("Sound", selection: $groove.manualRecipe.bassSound) {
                    Text("No bass").tag(Style?.none)
                    ForEach(Style.allCases) { Text($0.bassSoundTitle).tag(Style?.some($0)) }
                }
                menu("Pattern", selection: $groove.manualRecipe.bassPattern) {
                    ForEach(Style.allCases) { Text($0.bassPatternTitle).tag($0) }
                }
            case 3:
                menu("Sound", selection: $groove.manualRecipe.keys) {
                    Text("No keys").tag(Style?.none)
                    ForEach(Style.allCases) { Text($0.keysTitle).tag(Style?.some($0)) }
                }
            default:
                menu("Sound", selection: $groove.manualRecipe.texture) {
                    Text("No texture").tag(Style?.none)
                    ForEach(Style.allCases) { Text($0.textureTitle).tag(Style?.some($0)) }
                }
            }
            menu("Enters on", selection: $groove.manualRecipe.enter[track]) {
                ForEach(0..<8, id: \.self) { Text("Bar \($0 + 1)").tag($0) }
            }
        }
        .padding(.horizontal, 10)
    }

    private func menu<V: Hashable, Content: View>(_ label: String, selection: Binding<V>,
                                                  @ViewBuilder _ content: () -> Content) -> some View {
        Picker(label, selection: selection, content: content)
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .help(label)
    }
}

/// Key and chord-flavour menus shown next to the progression in manual mode.
struct HarmonyControls: View {
    @Bindable var groove: Groove

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Key", selection: $groove.manualRecipe.key) {
                ForEach(0..<12, id: \.self) { Text(noteNames[$0] + " minor").tag($0) }
            }
            Picker("Chords", selection: $groove.manualRecipe.harmony) {
                ForEach(Style.allCases) { Text($0.harmonyTitle).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 120)
    }
}
