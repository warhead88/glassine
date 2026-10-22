import SwiftUI

/// State of the recording controls: the options before recording, then the live recording.
@MainActor
@Observable
final class RecordingPanelModel {
    enum Phase: Equatable {
        case setup
        case countdown(Int)
        case recording
        case paused
        case saving
        case makingGIF(progress: Double)
    }

    var phase = Phase.setup {
        didSet { if phase.group != oldValue.group { onLayoutChange?() } }
    }
    var options: RecordingOptions {
        didSet {
            options.save()
            if options.format != oldValue.format { onLayoutChange?() }
        }
    }
    var side: PanelSide {
        didSet {
            UserDefaults.standard.set(side.rawValue, forKey: PrefKey.recordingPanelSide)
            onLayoutChange?()
        }
    }
    /// The audio track editor is open.
    var editingAudio = false
    /// Recorded time before the last pause, and when recording last (re)started.
    private(set) var elapsedBeforePause: TimeInterval = 0
    private(set) var runningSince: Date?

    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var onRecord: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onPause: (Bool) -> Void = { _ in }
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onDiscard: () -> Void = {}

    init(options: RecordingOptions) {
        self.options = options
        side = PanelSide(rawValue: UserDefaults.standard.string(forKey: PrefKey.recordingPanelSide) ?? "") ?? .right
    }

    var microphoneAvailable: Bool {
        if #available(macOS 15.0, *) { true } else { false }
    }

    func elapsed(at date: Date) -> TimeInterval {
        elapsedBeforePause + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    func startClock() {
        runningSince = .now
        phase = .recording
    }

    func togglePause() {
        if phase == .recording {
            elapsedBeforePause = elapsed(at: .now)
            runningSince = nil
            phase = .paused
            onPause(true)
        } else if phase == .paused {
            runningSince = .now
            phase = .recording
            onPause(false)
        }
    }
}

private extension RecordingPanelModel.Phase {
    /// Phases that look alike share a size.
    var group: Int {
        switch self {
        case .setup, .countdown: 0
        case .recording, .paused: 1
        case .saving, .makingGIF: 2
        }
    }
}

struct RecordingPanelView: View {
    let model: RecordingPanelModel
    /// The screen edge the panel is docked to; nil when it sits beside the area.
    var dockedEdge: PanelSide?

    private static let shoulder: CGFloat = 16

    private var vertical: Bool { model.side.isVertical }

    var body: some View {
        let shape = PanelShape(dockedEdge: dockedEdge, radius: 20, shoulder: Self.shoulder)
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            switch model.phase {
            case .setup, .countdown: setupControls
            case .recording, .paused: liveControls
            case .saving, .makingGIF: finishing
            }
        }
        .padding(contentInsets)
        .background {
            // The panel is its own SwiftUI root, so it reads the theme directly.
            if Theme.shared.showsPaperDetails {
                DotPattern().clipShape(shape)
            }
        }
        .paperPanel(in: shape)
        .padding(shadowInsets)
        .fixedSize()
        .animation(.snappy(duration: 0.2), value: model.options.format)
        .themed() // its own root: the panel's hosting view is typed by this view
    }

    // MARK: Phases

    @ViewBuilder
    private var setupControls: some View {
        RecordButton(countdown: countdown) { model.onRecord() }
            .disabled(countdown != nil)
        Separator(across: vertical)

        let options = model.options
        OptionChip(caption: "FORMAT", value: options.format == .video ? "MP4" : "GIF",
                   choices: [(RecordingFormat.video, "Video (MP4)"), (.gif, "GIF")], selection: options.format) {
            model.options.format = $0
        }
        if options.format == .video {
            OptionChip(caption: "CODEC", value: options.codec.title,
                       choices: VideoCodec.allCases.map { ($0, $0.menuTitle) }, selection: options.codec) {
                model.options.codec = $0
            }
            OptionChip(caption: "FPS", value: "\(options.framesPerSecond)",
                       choices: [(30, "30 fps"), (60, "60 fps")], selection: options.framesPerSecond) {
                model.options.framesPerSecond = $0
            }
            if options.codec.hasBitrate {
                OptionChip(caption: "BITRATE", value: options.bitrateMbps == 0 ? "Auto" : "\(options.bitrateMbps)M",
                           choices: [(0, "Automatic")] + [4, 8, 16, 32, 50].map { ($0, "\($0) Mbit/s") },
                           selection: options.bitrateMbps) {
                    model.options.bitrateMbps = $0
                }
            }
        } else {
            OptionChip(caption: "FPS", value: "\(options.gifFramesPerSecond)",
                       choices: [10, 15, 24].map { ($0, "\($0) fps") }, selection: options.gifFramesPerSecond) {
                model.options.gifFramesPerSecond = $0
            }
            OptionChip(caption: "WIDTH", value: options.gifMaxWidth == 0 ? "Full" : "\(options.gifMaxWidth)",
                       choices: [480, 640, 800, 1000].map { ($0, "Up to \($0) px") } + [(0, "As recorded")],
                       selection: options.gifMaxWidth) {
                model.options.gifMaxWidth = $0
            }
        }
        OptionChip(caption: "SCALE", value: options.retina ? "Retina" : "1×",
                   choices: [(true, "Retina (every pixel)"), (false, "1× (smaller files)")], selection: options.retina) {
            model.options.retina = $0
        }
        Separator(across: vertical)

        ToggleIcon(symbol: "cursorarrow", help: "Show the pointer", isOn: options.showsCursor) {
            model.options.showsCursor.toggle()
        }
        if options.format == .video {
            AudioChip(model: model)
        }
        Separator(across: vertical)

        PositionMenu(side: model.side) { model.side = $0 }
        PanelIconButton(symbol: "xmark", help: "Cancel (Esc)", tint: .ink2) { model.onCancel() }
            .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var liveControls: some View {
        LiveIndicator(model: model, vertical: vertical)
        Separator(across: vertical)
        PanelIconButton(symbol: model.phase == .paused ? "play.fill" : "pause.fill",
                        help: model.phase == .paused ? "Resume" : "Pause", tint: .ink) {
            model.togglePause()
        }
        PanelIconButton(symbol: "stop.fill", help: "Stop and save", tint: .rec) { model.onStop() }
        PanelIconButton(symbol: "trash", help: "Discard the recording", tint: .ink2) { model.onDiscard() }
    }

    @ViewBuilder
    private var finishing: some View {
        if case .makingGIF(let progress) = model.phase {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Making GIF…").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink2).fixedSize()
        } else {
            ProgressView().controlSize(.small)
            Text("Saving…").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink2).fixedSize()
        }
    }

    private var countdown: Int? {
        if case .countdown(let seconds) = model.phase { seconds } else { nil }
    }

    // MARK: Geometry

    /// Content stays clear of the shoulders and the glass edge.
    private var contentInsets: EdgeInsets {
        var insets = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        switch dockedEdge {
        case .right, .left:
            insets.top += Self.shoulder
            insets.bottom += Self.shoulder
        case .below, .above:
            insets.leading += Self.shoulder
            insets.trailing += Self.shoulder
        case nil:
            break
        }
        return insets
    }

    /// Room for the shadow, except along a docked edge, where the panel meets the screen.
    private var shadowInsets: EdgeInsets {
        var insets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        switch dockedEdge {
        case .right: insets.trailing = 0
        case .left: insets.leading = 0
        case .below: insets.bottom = 0
        case .above: insets.top = 0
        case nil: break
        }
        return insets
    }
}

private extension VideoCodec {
    var menuTitle: String {
        switch self {
        case .h264: "H.264 — plays everywhere"
        case .hevc: "HEVC (H.265) — half the size"
        case .prores: "ProRes 422 — for editing, large files"
        }
    }
}

// MARK: - Shape and texture

/// A rounded panel; docked, it flares into the screen edge with concave shoulders, like the area
/// frame does around the notch.
struct PanelShape: InsettableShape {
    var dockedEdge: PanelSide?
    var radius: CGFloat
    var shoulder: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard let edge = dockedEdge else {
            return Path(roundedRect: rect, cornerRadius: max(radius - insetAmount, 0), style: .continuous)
        }
        // Drawn docked to the right edge (thickness × length), then turned to the real edge.
        let vertical = edge.isVertical
        let thickness = vertical ? rect.width : rect.height
        let length = vertical ? rect.height : rect.width
        let canonical = Self.rightEdgePath(thickness: thickness, length: length,
                                           radius: max(radius - insetAmount, 0), shoulder: shoulder)
        let turn: CGAffineTransform = switch edge {
        case .right: .identity
        case .left: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: thickness, ty: 0)
        case .below: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .above: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: thickness)
        }
        return Path(canonical).applying(turn.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    /// The edge is the line x = thickness; shoulders at both ends curve into it.
    static func rightEdgePath(thickness w: CGFloat, length h: CGFloat, radius r: CGFloat, shoulder s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: s), tangent2End: CGPoint(x: 0, y: s), radius: s)
        path.addArc(tangent1End: CGPoint(x: 0, y: s), tangent2End: CGPoint(x: 0, y: h - s), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: h - s), tangent2End: CGPoint(x: w, y: h - s), radius: r)
        path.addArc(tangent1End: CGPoint(x: w, y: h - s), tangent2End: CGPoint(x: w, y: h), radius: s)
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PanelShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// A faint dot grid, like the perforation of glassine paper.
private struct DotPattern: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 7
            var dots = Path()
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(Color.ink.opacity(0.11)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

private struct RecordButton: View {
    let countdown: Int?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Red means recording, and only here (DECISIONS 2).
                Circle().fill(Color.rec)
                Circle().strokeBorder(.white, lineWidth: 2).padding(6.5)
                if let countdown {
                    Text("\(countdown)")
                        .font(Font(Typography.fraunces(size: 20, weight: 560)))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Circle().fill(.white).frame(width: 14, height: 14)
                }
            }
            .frame(width: 46, height: 46)
            .scaleEffect(hovered && countdown == nil ? 1.05 : 1)
            .shadow(color: Color.rec.opacity(0.35), radius: hovered ? 8 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .help("Record (↩)")
        .onHover { hovered = $0 }
        .animation(.snappy(duration: 0.15), value: hovered)
        .animation(.snappy, value: countdown)
    }
}

private struct OptionChip<Value: Hashable>: View {
    let caption: String
    let value: String
    let choices: [(Value, String)]
    let selection: Value
    let choose: (Value) -> Void
    @State private var hovered = false

    var body: some View {
        Menu {
            ForEach(choices, id: \.0) { choice, title in
                Button {
                    choose(choice)
                } label: {
                    if choice == selection { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            ChipFace(caption: caption, value: value, hovered: hovered)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
    }
}

/// A chip's face: the label on top, the value in Fraunces.
private struct ChipFace: View {
    let caption: String
    let value: String
    let hovered: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .textStyle(ThemeTokens.label)
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
            Text(value)
                .textStyle(ThemeTokens.chip)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 66, height: 42)
        .background(RoundedRectangle(cornerRadius: ThemeTokens.Radius.control, style: .continuous)
            .fill(hovered ? Color.rule : Color.key))
    }
}

private struct ToggleIcon: View {
    let symbol: String
    let help: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Theme.shared.onAccent : Color.ink2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? Theme.shared.accent : hovered ? Color.rule : Color.key))
                .overlay {
                    if !isOn {
                        // A slash marks "off" without a second symbol.
                        Capsule().fill(Color.ink3).frame(width: 1.5, height: 18).rotationEffect(.degrees(-45))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help + (isOn ? ": on" : ": off"))
        .onHover { hovered = $0 }
    }
}

private struct PanelIconButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovered ? Color.rule : Color.key))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
    }
}

private struct PositionMenu: View {
    let side: PanelSide
    let choose: (PanelSide) -> Void

    var body: some View {
        Menu {
            Section("Controls go") {
                ForEach(PanelSide.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        Label(option.title, systemImage: option == side ? "checkmark" : option.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: side.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.key))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Where the controls go: beside the area, or on that screen edge when there's no room")
    }
}

/// A tear-off line between groups: a row of perforation dots across the panel.
private struct Separator: View {
    /// The panel is a column, so the line runs across it.
    let across: Bool

    var body: some View {
        let layout = across ? AnyLayout(HStackLayout(spacing: 4.5)) : AnyLayout(VStackLayout(spacing: 4.5))
        layout {
            ForEach(0..<(across ? 7 : 4), id: \.self) { _ in
                Circle().fill(Color.border).frame(width: 2.6, height: 2.6)
            }
        }
        .padding(across ? .vertical : .horizontal, 2)
        .accessibilityHidden(true)
    }
}

/// A clock whose digits sit in fixed cells: Fraunces has no tabular figures, and the time
/// mustn't jitter as it counts.
struct TimerText: View {
    let text: String
    var style = ThemeTokens.timer

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .frame(width: style.size * (character == ":" ? 0.3 : 0.62))
            }
        }
        .font(Typography.font(style))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Red dots running like a level meter, and the time; still and grey while paused.
private struct LiveIndicator: View {
    let model: RecordingPanelModel
    let vertical: Bool

    var body: some View {
        let paused = model.phase == .paused
        TimelineView(.animation(minimumInterval: 1 / 20, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                let dots = vertical ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 3))
                dots {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(paused ? Color.ink3 : Color.rec)
                            .frame(width: 5, height: 5)
                            .opacity(paused ? 0.6 : 0.3 + 0.7 * max(0, sin(t * 5 - Double(index) * 0.8)))
                    }
                }
                TimerText(text: RecordingMath.clock(model.elapsed(at: context.date)))
                    .foregroundStyle(paused ? Color.ink3 : Color.ink)
            }
        }
    }
}

// MARK: - Audio tracks

/// "AUDIO · 2 tracks"; opens the track editor.
private struct AudioChip: View {
    @Bindable var model: RecordingPanelModel
    @State private var hovered = false

    var body: some View {
        let count = model.options.audioTracks.filter { !$0.sources.isEmpty }.count
        Button { model.editingAudio.toggle() } label: {
            ChipFace(caption: "Audio", value: count == 0 ? "Off" : count == 1 ? "1 track" : "\(count) tracks",
                     hovered: hovered || model.editingAudio)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Audio tracks: system audio, microphones, single apps")
        .popover(isPresented: $model.editingAudio, arrowEdge: arrowEdge) {
            AudioTracksEditor(model: model)
                .presentationBackground(Color.card)
        }
    }

    /// The editor opens away from the screen edge the controls are on.
    private var arrowEdge: Edge {
        switch model.side {
        case .right: .leading
        case .left: .trailing
        case .below: .top
        case .above: .bottom
        }
    }
}

private struct AudioTracksEditor: View {
    let model: RecordingPanelModel

    private var tracks: [AudioTrack] { model.options.audioTracks }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio").textStyle(ThemeTokens.chip).foregroundStyle(Color.ink)
                Text("Each track stays separate in the video; the sources in a track are mixed together.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if tracks.isEmpty {
                Text("No sound. Add a track for system audio, a microphone or single apps.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackCard(model: model, track: track, number: index + 1)
            }

            Button {
                model.options.audioTracks.append(AudioTrack())
            } label: {
                Label("Add Track", systemImage: "plus")
            }
            .buttonStyle(.paperSecondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct TrackCard: View {
    let model: RecordingPanelModel
    let track: AudioTrack
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Track \(number)").textStyle(ThemeTokens.label).foregroundStyle(Color.ink3)
                Spacer()
                Button {
                    model.options.audioTracks.removeAll { $0.id == track.id }
                } label: {
                    Image(systemName: "trash").foregroundStyle(Color.ink2)
                }
                .buttonStyle(.plain)
                .help("Remove the track")
            }
            ForEach(track.sources, id: \.self) { source in
                HStack(spacing: 8) {
                    Group {
                        if let icon = AudioSourceCatalog.icon(for: source) {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: source.symbol).foregroundStyle(Color.ink2)
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(source.title).foregroundStyle(Color.ink).lineLimit(1)
                    Spacer()
                    Button {
                        update { $0.sources.removeAll { $0 == source } }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from the track")
                }
                .font(.system(size: 13))
            }
            AddSourceMenu(model: model) { source in update { $0.sources.append(source) } }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: ThemeTokens.Radius.control, style: .continuous).fill(Color.key))
    }

    private func update(_ change: (inout AudioTrack) -> Void) {
        guard let index = model.options.audioTracks.firstIndex(where: { $0.id == track.id }) else { return }
        change(&model.options.audioTracks[index])
    }
}

/// System audio, microphones and running apps — each only once across tracks.
private struct AddSourceMenu: View {
    let model: RecordingPanelModel
    let add: (AudioSource) -> Void

    var body: some View {
        let tracks = model.options.audioTracks
        let system = AudioTrackPlan.available([.system], in: tracks)
        let microphones = AudioTrackPlan.available(AudioSourceCatalog.microphones, in: tracks)
        let apps = AudioSourceCatalog.apps.filter { AudioTrackPlan.available([$0.source], in: tracks).count == 1 }
        Menu {
            if !system.isEmpty {
                Button { add(.system) } label: { Label("System Audio (all apps)", systemImage: "speaker.wave.2.fill") }
            }
            Section(model.microphoneAvailable ? "Microphones" : "Microphones (macOS 15 or later)") {
                ForEach(microphones, id: \.self) { microphone in
                    Button { add(microphone) } label: { Label(microphone.title, systemImage: "mic.fill") }
                }
            }
            .disabled(!model.microphoneAvailable)
            Section("Apps") {
                ForEach(apps, id: \.source) { app in
                    Button { add(app.source) } label: {
                        Label {
                            Text(app.source.title)
                        } icon: {
                            if let icon = app.icon { Image(nsImage: Self.menuIcon(icon)) }
                        }
                    }
                }
            }
        } label: {
            Label("Add Source", systemImage: "plus.circle")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.shared.accent)
        .fixedSize()
    }

    private static func menuIcon(_ icon: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        image.unlockFocus()
        return image
    }
}

