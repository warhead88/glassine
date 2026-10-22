import KeyboardShortcuts
import SwiftUI

/// Shown on first launch and whenever a capture is attempted without Screen Recording access.
struct WelcomeView: View {
    var openSettings: () -> Void
    var close: () -> Void

    @State private var hasAccess = ScreenAccess.isGranted && !Self.debugShowsSteps
    @State private var prompted = ScreenAccess.hasPrompted && !Self.debugShowsSteps
    @State private var conflicts = SystemScreenshotShortcuts.conflicts

    /// Debug (`--debug-welcome`): show the permission steps even when access is granted.
    nonisolated(unsafe) static var debugShowsSteps = false

    private static let shortcuts: [[(String, KeyboardShortcuts.Name)]] = [
        [("Capture area", .captureArea), ("Capture window", .captureWindow), ("Capture screen", .captureScreen),
         ("Record screen", .recordScreen)],
        [("Copy text", .captureText), ("Pick a color", .pickColor), ("Measure", .measure), ("Settings", .openSettings)],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The stamp sits in the corner on its own; the title runs under it on one line.
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome to Glassine")
                        .textStyle(ThemeTokens.display)
                        .foregroundStyle(Color.ink)
                        .fixedSize()
                    Text("A quiet screenshot tool. It runs in the background and wakes up on a few shortcuts.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(.top, 52)
                .frame(maxWidth: .infinity, alignment: .leading)
                StampInSleeve(caption: Self.versionCaption)
            }

            VStack(alignment: .leading, spacing: 10) {
                SettingsLabel("Shortcuts")
                HStack(alignment: .top, spacing: 20) {
                    ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { column, rows in
                        if column > 0 { Rectangle().fill(Color.rule).frame(width: 1) }
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                if index > 0 { RowDivider() }
                                HStack {
                                    Text(row.0).font(.system(size: 14)).foregroundStyle(Color.ink)
                                    Spacer(minLength: 8)
                                    if let shortcut = KeyboardShortcuts.getShortcut(for: row.1) {
                                        KeyCaps(shortcut: shortcut.description)
                                    } else {
                                        Text("Not set").font(.system(size: 12)).foregroundStyle(Color.ink3)
                                    }
                                }
                                .frame(height: 40)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
                .background(Color.card, in: RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous).strokeBorder(Color.border))
            }

            if hasAccess {
                VStack(alignment: .leading, spacing: 14) {
                    Done(title: "Screen Recording is on",
                         detail: "macOS asks about once a month whether Glassine can still see your screen. Choose Allow.")
                    if conflicts.isEmpty {
                        Done(title: "macOS screenshot shortcuts are off", detail: Self.screenshotKeysDetail)
                    } else {
                        ShortcutConflictNote(conflicts: conflicts)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allow Screen Recording")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("macOS asks every screenshot app for this. It takes three steps:")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink2)
                    PermissionStep(number: 1, isDone: prompted, text: prompted
                                   ? "macOS has asked once already — open System Settings with the button below."
                                   : "Click the button below. macOS asks — choose “Open System Settings”.")
                    PermissionStep(number: 2, isDone: false,
                                   text: "Turn on Glassine under Screen & System Audio Recording.")
                    PermissionStep(number: 3, isDone: false,
                                   text: "When macOS offers “Quit & Reopen”, click it. Glassine comes back ready.")
                    Button(ScreenAccess.requestTitle) {
                        ScreenAccess.request()
                        prompted = ScreenAccess.hasPrompted
                    }
                    .buttonStyle(.paperPrimary)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 4)
                    if !conflicts.isEmpty {
                        ShortcutConflictNote(conflicts: conflicts).padding(.top, 6)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Everything stays on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
                Spacer()
                if hasAccess {
                    Button("Open Settings", action: openSettings).buttonStyle(.paperSecondary)
                    Button("Start Capturing", action: close)
                        .buttonStyle(.paperPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Settings", action: openSettings).buttonStyle(.paperQuiet)
                    Button("Later", action: close).buttonStyle(.paperSecondary)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .padding(.bottom, 28)
        .frame(width: 640)
        .fixedSize()
        .background(Color.paper)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = ScreenAccess.isGranted && !Self.debugShowsSteps
            conflicts = SystemScreenshotShortcuts.conflicts
        }
    }

    /// "0.4" for the stamp: the version without its patch number.
    private static var versionCaption: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// "⇧⌘3, ⇧⌘4 and ⇧⌘5 now open Glassine."
    private static var screenshotKeysDetail: String {
        let keys = [KeyboardShortcuts.Name.captureScreen, .captureArea, .captureWindow]
            .compactMap { KeyboardShortcuts.getShortcut(for: $0)?.description }
        return keys.isEmpty ? "Glassine's shortcuts reach it from any app."
            : "\(keys.formatted(.list(type: .and))) now open Glassine."
    }
}

/// A finished step: the sage check, a title, a line of detail.
private struct Done: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckBadge()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionStep: View {
    let number: Int
    let isDone: Bool
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if isDone {
                    CheckBadge(size: 22)
                } else {
                    Text("\(number)")
                        .font(Font(Typography.fraunces(size: 13, weight: 500)))
                        .foregroundStyle(Color.ink)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.key))
                        .overlay(Circle().strokeBorder(Color.border))
                }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(isDone ? Color.ink2 : Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// macOS keeps ⇧⌘3/4/5 while its own screenshot shortcuts are on; explains where to turn them off.
struct ShortcutConflictNote: View {
    let conflicts: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.ochre)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text("macOS still uses \(conflicts.joined(separator: ", ")) for its own screenshots")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("Turn them off so Glassine gets them: Keyboard → Keyboard Shortcuts… → Screenshots.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Keyboard Settings…", action: SystemScreenshotShortcuts.openSettings)
                    .buttonStyle(.paperSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous).strokeBorder(Color.border))
    }
}
