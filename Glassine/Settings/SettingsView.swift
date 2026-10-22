import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettings().tabItem { Label("Capture", systemImage: "viewfinder") }
            OutputSettings().tabItem { Label("Output", systemImage: "square.and.arrow.down") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 600, height: 700)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasScreenAccess = ScreenAccess.isGranted

    var body: some View {
        Form {
            Section {
                OptionCards(title: "Menu bar icon", note: "Without the icon, use shortcuts — or open Glassine again from Spotlight to get here.",
                            options: [(false, "Hidden"), (true, "Shown")], selection: $showMenuBarIcon) { on in
                    MenuBarIconPreview(on: on)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section("Permissions") {
                LabeledContent("Screen Recording:") {
                    if hasScreenAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(ScreenAccess.requestTitle, action: ScreenAccess.request)
                    }
                }
            }

            Section {
                HStack {
                    Text("Return here with the settings shortcut, or by opening Glassine again from Spotlight.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Glassine") { NSApp.terminate(nil) }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uninstall Glassine")
                        Text("Moves the app, its settings and caches to the Trash and removes its permissions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Uninstall…", role: .destructive) { Uninstaller.confirmAndRun() }
                }
            }
        }
        .formStyle(.grouped)
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
    @AppStorage(PrefKey.colorFormat) private var colorFormat = ColorFormat.hex.rawValue
    @AppStorage(PrefKey.captureStartSound) private var startSound = true
    @AppStorage(PrefKey.areaFrameStyle) private var frameStyle = AreaFrameStyle.notch.rawValue
    @AppStorage(PrefKey.playSound) private var afterCaptureSound = true

    var body: some View {
        Form {
            Section("Area Capture") {
                OptionCards(title: "Screen frame", note: "Displays without a notch always get the straight frame.",
                            options: AreaFrameStyle.allCases.map { ($0.rawValue, $0.title) }, selection: $frameStyle) { style in
                    FrameStylePreview(style: AreaFrameStyle(rawValue: style) ?? .notch)
                }
                OptionCards(title: "After selecting an area",
                            options: [(false, "Capture at once"), (true, "Adjust, then ↩")], selection: $adjustBeforeCapture) { adjust in
                    SelectionModePreview(adjust: adjust)
                }
                OptionCards(title: "Magnifier", note: "Press M while capturing to switch on the fly.",
                            options: [(true, "Magnifier"), (false, "Crosshair only")], selection: $showMagnifier) { on in
                    MagnifierPreview(on: on)
                }
            }

            Section("Window Capture") {
                OptionCards(title: "Window shadow",
                            options: [(true, "With shadow"), (false, "No shadow")], selection: $windowShadow) { shadow in
                    WindowShadowPreview(shadow: shadow)
                }
            }

            Section("Color Picker") {
                OptionCards(title: "Copied format",
                            options: ColorFormat.allCases.map { ($0.rawValue, $0.rawValue.uppercased()) }, selection: $colorFormat) { format in
                    ColorFormatPreview(format: ColorFormat(rawValue: format) ?? .hex)
                }
            }

            Section {
                Picker("Timer:", selection: $timerDelay) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }

            Section("Sounds") {
                Toggle("When area capture starts", isOn: $startSound)
                Toggle("After capture", isOn: $afterCaptureSound)
            }

            Section("Tips") {
                VStack(alignment: .leading, spacing: 4) {
                    tip("Drag", "select an area")
                    tip("Space", "switch between area and window capture")
                    tip("⇧ Shift", "square selection")
                    tip("⌥ Option", "select from the center")
                    tip("Space ⇢", "hold while dragging to move the selection")
                    tip("M", "show or hide the magnifier")
                    tip("C", "copy the color under the pointer")
                    tip("Esc", "cancel")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private func tip(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).fontWeight(.medium).frame(width: 80, alignment: .leading)
            Text(text).foregroundStyle(.secondary)
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
        Form {
            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                Toggle("Save to folder", isOn: $saveToFile)
                LabeledContent("Folder:") {
                    HStack {
                        Text((saveFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                .disabled(!saveToFile)
            }

            Section("Preview") {
                OptionCards(title: "After a capture", note: "Drag the preview into any app, or click it to edit.",
                            options: [(true, "Show preview"), (false, "No preview")], selection: $showQuickAccess) { on in
                    QuickAccessPreview(on: on)
                }
                Picker("Close preview:", selection: $quickAccessAutoClose) {
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                    Text("Never").tag(0)
                }
                .disabled(!showQuickAccess)
            }

            Section("Files") {
                Picker("Format:", selection: $imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0.rawValue) }
                }
                TextField("Name prefix:", text: $fileNamePrefix)
                LabeledContent("Example:") {
                    Text(exampleName).foregroundStyle(.secondary)
                }
                Toggle("Save Retina captures at standard resolution (1x)", isOn: $saveAtStandardResolution)
            }
        }
        .formStyle(.grouped)
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
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture area:", name: .captureArea)
                KeyboardShortcuts.Recorder("Capture window:", name: .captureWindow)
                KeyboardShortcuts.Recorder("Capture screen:", name: .captureScreen)
                KeyboardShortcuts.Recorder("Repeat last area:", name: .repeatLastArea)
                KeyboardShortcuts.Recorder("Capture with timer:", name: .timedCapture)
                KeyboardShortcuts.Recorder("Copy text from screen:", name: .captureText)
                KeyboardShortcuts.Recorder("Pick color:", name: .pickColor)
                KeyboardShortcuts.Recorder("Measure:", name: .measure)
                KeyboardShortcuts.Recorder("Pin from clipboard:", name: .pinFromClipboard)
                KeyboardShortcuts.Recorder("Show/hide pins:", name: .togglePins)
                KeyboardShortcuts.Recorder("Open settings:", name: .openSettings)
            }
            Section {
                Text("Shortcuts use physical key positions: with a Russian layout, ⌥⇧⌘, is the Б key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
