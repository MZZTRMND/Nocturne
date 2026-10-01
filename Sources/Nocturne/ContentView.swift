import SwiftUI

extension Style {
    var accent: Color {
        switch self {
        case .tripHop: Color(red: 1.0, green: 0.62, blue: 0.28)
        case .industrial: Color(red: 0.96, green: 0.34, blue: 0.34)
        case .techno: Color(red: 0.25, green: 0.6, blue: 1.0)
        }
    }
}

/// Transport, knobs and recording on the left; progression, keyboard and tracks on the
/// right. The window's title and the shortcuts help live in the native toolbar.
struct ContentView: View {
    @Bindable var groove: Groove
    @State private var showShortcuts = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    TransportCard(groove: groove)
                    KnobPanel(groove: groove)
                    RecordCard(groove: groove)
                }
                .frame(width: 250)
                .frame(maxHeight: .infinity)

                VStack(spacing: 14) {
                    ProgressionPanel(groove: groove)
                    PianoPanel(groove: groove)
                    MixerRow(groove: groove)
                }
                .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding([.horizontal, .bottom], 14)
        .padding(.top, 6)
        .frame(width: 1026)
        .background { Backdrop(accent: groove.style.accent, energy: groove.levels[0]) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShortcuts.toggle()
                } label: {
                    Image(systemName: "command")
                }
                .keyboardShortcut("/")
                .help("Shortcuts and keyboard (⌘/)")
                .accessibilityLabel("Shortcuts and keyboard")
                .popover(isPresented: $showShortcuts, arrowEdge: .bottom) { ShortcutsView() }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(groove.style.accent)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.5), value: groove.style)
    }
}

// MARK: - Left

private struct TransportCard: View {
    @Bindable var groove: Groove

    var body: some View {
        HStack(spacing: 14) {
            Button {
                groove.isPlaying.toggle()
            } label: {
                Image(systemName: groove.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .help(groove.isPlaying ? "Stop (Space)" : "Play (Space)")

            VStack(alignment: .leading, spacing: 2) {
                Text(groove.currentChord)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: groove.currentChord)
                Text("\(Int(groove.bpm.rounded())) bpm · \(groove.style.keyName)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Style", selection: $groove.style) {
                    ForEach(Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Style: \(groove.style.title)")
            .accessibilityLabel("Style, \(groove.style.title)")
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

/// Big record button, elapsed time and a live timeline of the take's levels.
private struct RecordCard: View {
    let groove: Groove

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    groove.toggleRecording()
                } label: {
                    Group {
                        if groove.isRecording {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 16, height: 16)
                        } else {
                            Circle().fill(.red).frame(width: 20, height: 20)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)     // untinted, so the dot stays red
                .disabled(groove.isSavingTake)
                .help(groove.isRecording ? "Stop recording and save (⌘R)" : "Record (⌘R)")
                .accessibilityLabel(groove.isRecording ? "Stop recording" : "Record")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Record").font(.headline)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(groove.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Spacer(minLength: 0)
                elapsed
            }
            TakeTimeline(levels: groove.takeLevels, recording: groove.isRecording)
                .frame(height: 30)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var status: String {
        if groove.isRecording { return "Recording…" }
        if groove.isSavingTake { return "Saving…" }
        return groove.takeLevels.isEmpty ? "Ready" : "Last take"
    }

    @ViewBuilder private var elapsed: some View {
        if let started = groove.recordingStarted {
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                Self.clock(ctx.date.timeIntervalSince(started)).foregroundStyle(.red)
            }
        } else {
            Self.clock(groove.lastTakeDuration).foregroundStyle(.secondary)
        }
    }

    private static func clock(_ t: TimeInterval) -> some View {
        let secs = max(0, Int(t))
        return Text("\(secs / 60):\(String(format: "%02d", secs % 60))")
            .font(.title3.weight(.semibold).monospacedDigit())
    }
}

/// A row of dots: idle ones are small and grey; recorded ones grow with the take's level,
/// red while recording and dimmed afterwards. Scrolls once the row is full.
private struct TakeTimeline: View {
    let levels: [Double]
    let recording: Bool
    private let count = 36

    var body: some View {
        let recent = Array(levels.suffix(count))
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Group {
                    if i < recent.count {
                        Capsule()
                            .fill(recording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .frame(width: 3.5, height: 4 + 24 * recent[i])
                    } else {
                        Circle().fill(.white.opacity(0.16)).frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.linear(duration: 0.1), value: levels.count)
        .accessibilityHidden(true)
    }
}

/// The four bars of the loop side by side: past steps light up, hits are drawn larger.
private struct ProgressionPanel: View {
    let groove: Groove

    var body: some View {
        let p = groove.pattern
        HStack(spacing: 22) {
            ForEach(0..<4, id: \.self) { b in
                let isCurrentBar = groove.isPlaying && groove.bar == b
                VStack(alignment: .leading, spacing: 7) {
                    Text(p.chordNames[b])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrentBar ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    HStack(spacing: 0) {
                        ForEach(0..<16, id: \.self) { s in
                            let hit = p.kick[b][s] > 0.5 || p.snare[b][s] > 0.5
                            let lit = groove.step >= 0 && (b < groove.bar || (b == groove.bar && s <= groove.step))
                            let now = groove.step == s && groove.bar == b
                            Circle()
                                .fill(lit ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(hit ? 0.35 : 0.16)))
                                .frame(width: now ? 9 : (hit ? 7 : 4.5), height: now ? 9 : (hit ? 7 : 4.5))
                                .shadow(color: now ? groove.style.accent : .clear, radius: 6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression")
        .accessibilityValue(p.chordNames.joined(separator: ", "))
    }
}

// MARK: - Middle

private struct MixerRow: View {
    @Bindable var groove: Groove

    var body: some View {
        HStack(spacing: 12) {
            ForEach($groove.tracks) { $track in
                TrackCard(track: $track,
                          name: groove.trackName(track.id),
                          level: groove.levels[track.id],
                          accent: groove.style.accent)
            }
        }
    }
}

private struct TrackCard: View {
    @Binding var track: Track
    let name: String
    let level: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: track.icon)
                    .font(.body)
                    .foregroundStyle(.tint)
                    .opacity(track.muted ? 0.3 : 0.45 + 0.55 * level)
                    .scaleEffect(1 + 0.12 * level)
                    .frame(width: 20)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 2)
                Button {
                    track.muted.toggle()
                } label: {
                    Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(track.muted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(track.muted ? "Unmute \(name)" : "Mute \(name)")
                .accessibilityLabel(track.muted ? "Unmute \(name)" : "Mute \(name)")
            }
            Slider(value: $track.volume, in: 0...1)
                .controlSize(.small)
                .disabled(track.muted)
                .accessibilityLabel("\(name) volume")
        }
        .padding(12)
        .glassEffect(.regular.tint(track.muted ? .clear : accent.opacity(0.06 + 0.16 * level)),
                     in: .rect(cornerRadius: 22))
    }
}

// MARK: - Right

private struct KnobPanel: View {
    @Bindable var groove: Groove

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 18) {
            GridRow {
                Knob(title: "Tempo",
                     value: Binding(get: { (groove.bpm - 60) / 100 }, set: { groove.bpm = 60 + $0 * 100 }),
                     display: "\(Int(groove.bpm.rounded())) bpm",
                     defaultValue: (groove.style.defaults.bpm - 60) / 100)
                Knob(title: "Swing", value: $groove.swing,
                     display: percent(groove.swing), defaultValue: groove.style.defaults.swing)
                Knob(title: "Tone", value: $groove.tone,
                     display: groove.tone < 0.35 ? "Dark" : groove.tone > 0.8 ? "Open" : percent(groove.tone),
                     defaultValue: groove.style.defaults.tone)
            }
            GridRow {
                Knob(title: "Grit", value: $groove.grit,
                     display: percent(groove.grit), defaultValue: groove.style.defaults.grit)
                Knob(title: "Space", value: $groove.space,
                     display: percent(groove.space), defaultValue: groove.style.defaults.space)
                Knob(title: "Volume", value: $groove.volume,
                     display: percent(groove.volume), defaultValue: 0.8)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

// MARK: - Background

/// Slowly drifting dark mesh tinted by the style colour, breathing with the drums.
private struct Backdrop: View {
    let accent: Color
    let energy: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = Float(ctx.date.timeIntervalSinceReferenceDate)
            let a = 0.18 * sin(t * 0.21), b = 0.15 * cos(t * 0.17)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5 + b], [0.5 + a, 0.5 - b * 0.5], [1, 0.5 - a],
                    [0, 1], [0.5 - a * 0.6, 1], [1, 1],
                ],
                colors: [
                    .black, Color(white: 0.05), .black,
                    accent.opacity(0.22), accent.opacity(0.42 + 0.25 * energy),
                    Color(red: 0.14, green: 0.06, blue: 0.28).opacity(0.8),
                    .black, accent.opacity(0.16), .black,
                ]
            )
        }
        .background(.black)
        .ignoresSafeArea()
    }
}
