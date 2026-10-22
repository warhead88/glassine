import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let updater: Updater
    @State private var tab = SettingsTab.initial

    var body: some View {
        VStack(spacing: 14) {
            SettingsTabs(tabs: SettingsTab.allCases, title: \.title, selection: $tab)
            switch tab {
            case .general: GeneralSettings()
            case .capture: CaptureSettings()
            case .output: OutputSettings()
            case .shortcuts: ShortcutSettings()
            }
        }
        .padding(.top, 4)
        .frame(width: 620, height: 720)
        .background(Color.paper)
        .environment(updater)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, output, shortcuts

    var id: Self { self }

    /// General; a debug build opens `--debug-settings <tab>` on that tab.
    static var initial: SettingsTab {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--debug-settings"), index + 1 < arguments.count,
           let tab = SettingsTab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return .general
    }

    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .output: "Output"
        case .shortcuts: "Shortcuts"
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasScreenAccess = ScreenAccess.isGranted
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        SettingsPage {
            SettingsSection(title: "Menu bar") {
                OptionCards(title: "Menu bar icon",
                            note: "Without the icon, use shortcuts — or open Glassine again from Spotlight to get here.",
                            options: [(false, "Hidden"), (true, "Shown")], selection: $showMenuBarIcon) { on in
                    MenuBarIconPreview(on: on)
                }
                SettingsCard {
                    SettingsRow("Launch at login", isOn: $launchAtLogin)
                }
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            SettingsSection(title: "Appearance") {
                SettingsCard {
                    SettingsRow(title: "Accent color", detail: "Buttons, switches and selection. Red stays for recording.") {
                        AccentPicker()
                    }
                }
            }

            SettingsSection(title: "Permissions") {
                SettingsCard {
                    SettingsRow(title: "Screen Recording") {
                        if hasScreenAccess {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.sageDeep)
                        } else {
                            Button(ScreenAccess.requestTitle, action: ScreenAccess.request)
                        }
                    }
                }
            }

            SettingsSection(title: "Updates") {
                SettingsCard {
                    SettingsRow("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    RowDivider()
                    SettingsRow(title: "Version \(Updater.currentVersion)") {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                    }
                }
            }

            SettingsSection(title: "About") {
                SettingsCard {
                    SettingsRow(title: "Free software under the GNU GPL v3") {
                        Button("Acknowledgements…") {
                            if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    RowDivider()
                    SettingsRow(title: "Quit Glassine",
                                detail: "Return here with the settings shortcut, or by opening Glassine again from Spotlight.") {
                        Button("Quit") { NSApp.terminate(nil) }
                    }
                    RowDivider()
                    SettingsRow(title: "Uninstall Glassine",
                                detail: "Moves the app, its settings and caches to the Trash and removes its permissions.") {
                        Button("Uninstall…", role: .destructive) { Uninstaller.confirmAndRun() }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenAccess = ScreenAccess.isGranted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct CaptureSettings: View {
    @AppStorage(PrefKey.showMagnifier) private var showMagnifier = true
    @AppStorage(PrefKey.adjustBeforeCapture) private var adjustBeforeCapture = false
    @AppStorage(PrefKey.windowShadow) private var windowShadow = true
    @AppStorage(PrefKey.timerDelay) private var timerDelay = 5
    @AppStorage(PrefKey.recordingCountdown) private var recordingCountdown = 3
    @AppStorage(PrefKey.colorFormat) private var colorFormat = ColorFormat.hex.rawValue
    @AppStorage(PrefKey.captureStartSound) private var startSound = true
    @AppStorage(PrefKey.areaFrameStyle) private var frameStyle = AreaFrameStyle.notch.rawValue
    @AppStorage(PrefKey.frameBottomCorners) private var bottomCorners = FrameBottomCorners.rounded.rawValue
    @AppStorage(PrefKey.playSound) private var afterCaptureSound = true

    private var frameIsOff: Bool { frameStyle == AreaFrameStyle.off.rawValue }

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Area capture") {
                OptionCards(title: "Screen frame", note: "Displays without a notch always get the straight frame.",
                            options: AreaFrameStyle.allCases.map { ($0.rawValue, $0.title) }, selection: $frameStyle) { style in
                    FrameStylePreview(style: AreaFrameStyle(rawValue: style) ?? .notch,
                                      bottom: FrameBottomCorners(rawValue: bottomCorners) ?? .rounded)
                }
                OptionCards(title: "Frame bottom corners", note: "MacBook screens are square at the bottom; windows are rounded.",
                            options: FrameBottomCorners.allCases.map { ($0.rawValue, $0.title) }, selection: $bottomCorners) { corners in
                    FrameCornerPreview(bottom: FrameBottomCorners(rawValue: corners) ?? .rounded)
                }
                .disabled(frameIsOff)
                .opacity(frameIsOff ? 0.45 : 1)
                OptionCards(title: "After selecting an area",
                            options: [(false, "Capture at once"), (true, "Adjust, then ↩")], selection: $adjustBeforeCapture) { adjust in
                    SelectionModePreview(adjust: adjust)
                }
                OptionCards(title: "Magnifier", note: "Press M while capturing to switch on the fly.",
                            options: [(true, "Magnifier"), (false, "Crosshair only")], selection: $showMagnifier) { on in
                    MagnifierPreview(on: on)
                }
                SettingsCard {
                    SettingsRow(title: "Capture with timer", detail: "Time to open a menu or hover before the capture.") {
                        Picker("Capture with timer", selection: $timerDelay) {
                            Text("3 seconds").tag(3)
                            Text("5 seconds").tag(5)
                            Text("10 seconds").tag(10)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            SettingsSection(title: "Window capture") {
                OptionCards(title: "Window shadow",
                            options: [(true, "With shadow"), (false, "No shadow")], selection: $windowShadow) { shadow in
                    WindowShadowPreview(shadow: shadow)
                }
            }

            SettingsSection(title: "Screen recording",
                            note: "The countdown runs inside the record button. Off starts recording as soon as you press it.") {
                SettingsCard {
                    SettingsRow(title: "Countdown before recording") {
                        Picker("Countdown before recording", selection: $recordingCountdown) {
                            Text("Off").tag(0)
                            Text("3 seconds").tag(3)
                            Text("5 seconds").tag(5)
                            Text("10 seconds").tag(10)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            SettingsSection(title: "Color picker") {
                OptionCards(title: "Copied format",
                            options: ColorFormat.allCases.map { ($0.rawValue, $0.rawValue.uppercased()) }, selection: $colorFormat) { format in
                    ColorFormatPreview(format: ColorFormat(rawValue: format) ?? .hex)
                }
            }

            SettingsSection(title: "Sounds") {
                SettingsCard {
                    SettingsRow("When area capture starts", isOn: $startSound)
                    RowDivider()
                    SettingsRow("After capture", isOn: $afterCaptureSound)
                }
            }

            SettingsSection(title: "While capturing") {
                SettingsCard {
                    let tips = [("Drag", "Select an area"), ("Space", "Switch between area and window capture"),
                                ("⇧ Shift", "Square selection"), ("⌥ Option", "Select from the center"),
                                ("Space ⇢", "Hold while dragging to move the selection"), ("M", "Show or hide the magnifier"),
                                ("C", "Copy the color under the pointer"), ("Esc", "Cancel")]
                    ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            Text(tip.0)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.ink)
                                .frame(width: 84, alignment: .leading)
                            Text(tip.1)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.ink2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

private struct OutputSettings: View {
    @AppStorage(PrefKey.copyToClipboard) private var copyToClipboard = true
    @AppStorage(PrefKey.saveToFile) private var saveToFile = true
    @AppStorage(PrefKey.saveFolder) private var saveFolder = AppPaths.defaultSaveFolder.path
    @AppStorage(PrefKey.showQuickAccess) private var showQuickAccess = true
    @AppStorage(PrefKey.quickAccessAutoClose) private var quickAccessAutoClose = 10
    @AppStorage(PrefKey.imageFormat) private var imageFormat = ImageFormat.png.rawValue
    @AppStorage(PrefKey.fileNamePrefix) private var fileNamePrefix = "Glassine"
    @AppStorage(PrefKey.saveAtStandardResolution) private var saveAtStandardResolution = false

    var body: some View {
        SettingsPage {
            SettingsSection(title: "After capture") {
                SettingsCard {
                    SettingsRow("Copy to clipboard", isOn: $copyToClipboard)
                    RowDivider()
                    SettingsRow("Save to folder", isOn: $saveToFile)
                    RowDivider()
                    SettingsRow(title: "Folder", detail: (saveFolder as NSString).abbreviatingWithTildeInPath) {
                        Button("Choose…", action: chooseFolder)
                    }
                    .disabled(!saveToFile)
                }
            }

            SettingsSection(title: "Preview") {
                OptionCards(title: "After a capture", note: "Drag the preview into any app, or click it to edit.",
                            options: [(true, "Show preview"), (false, "No preview")], selection: $showQuickAccess) { on in
                    QuickAccessPreview(on: on)
                }
                SettingsCard {
                    SettingsRow(title: "Close the preview") {
                        Picker("Close the preview", selection: $quickAccessAutoClose) {
                            Text("After 5 seconds").tag(5)
                            Text("After 10 seconds").tag(10)
                            Text("After 30 seconds").tag(30)
                            Text("Never").tag(0)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .disabled(!showQuickAccess)
                }
            }

            SettingsSection(title: "Files") {
                SettingsCard {
                    SettingsRow(title: "Format") {
                        Picker("Format", selection: $imageFormat) {
                            ForEach(ImageFormat.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    RowDivider()
                    SettingsRow(title: "Name prefix", detail: exampleName) {
                        TextField("Name prefix", text: $fileNamePrefix)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                    RowDivider()
                    SettingsRow("Save Retina captures at standard resolution (1x)", isOn: $saveAtStandardResolution)
                }
            }
        }
    }

    private var exampleName: String {
        let ext = (ImageFormat(rawValue: imageFormat) ?? .png).fileExtension
        return "\(Preferences.fileNamePrefix) 2026-10-21 at 19.53.06.\(ext)"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(filePath: saveFolder)
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}

private struct ShortcutSettings: View {
    @State private var conflicts = SystemScreenshotShortcuts.conflicts

    private static let shortcuts: [(String, KeyboardShortcuts.Name)] = [
        ("Capture area", .captureArea), ("Capture window", .captureWindow), ("Capture screen", .captureScreen),
        ("Repeat last area", .repeatLastArea), ("Capture with timer", .timedCapture),
        ("Copy text from screen", .captureText), ("Pick color", .pickColor), ("Measure", .measure),
        ("Record screen", .recordScreen), ("Pin from clipboard", .pinFromClipboard),
        ("Show or hide pins", .togglePins), ("Open settings", .openSettings),
    ]

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Shortcuts",
                            note: "Shortcuts use physical key positions: with a Russian layout, ⌥⇧⌘, is the Б key. "
                                + "Press the record shortcut again to start recording, and once more to stop.") {
                if !conflicts.isEmpty {
                    ShortcutConflictNote(conflicts: conflicts)
                }
                SettingsCard {
                    ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                        if index > 0 { RowDivider() }
                        SettingsRow(title: shortcut.0) {
                            KeyboardShortcuts.Recorder(for: shortcut.1)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            conflicts = SystemScreenshotShortcuts.conflicts
        }
    }
}

/// A row of accent swatches; System (the color picked in System Settings) comes first.
private struct AccentPicker: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccentChoice.allCases) { choice in
                let selected = theme.accentChoice == choice
                Button {
                    theme.accentChoice = choice
                } label: {
                    Circle()
                        .fill(swatch(choice))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? swatch(choice) : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Text(theme.accentChoice.title)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
    }

    private func swatch(_ choice: AccentChoice) -> Color {
        switch choice {
        case .system: Color(nsColor: .controlAccentColor)
        case .ink: Color(.accentInk)
        case .sage: Color(.accentSage)
        case .stamp: Color(.accentStamp)
        case .ochre: Color(.accentOchre)
        }
    }
}

