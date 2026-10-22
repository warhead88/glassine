import KeyboardShortcuts
import SwiftUI

/// Shown on first launch and whenever a capture is attempted without Screen Recording access.
struct WelcomeView: View {
    var openSettings: () -> Void
    var close: () -> Void

    @State private var hasAccess = ScreenAccess.isGranted && !Self.debugShowsSteps
    @State private var prompted = ScreenAccess.hasPrompted && !Self.debugShowsSteps

    /// Debug (`--debug-welcome`): show the permission steps even when access is granted.
    nonisolated(unsafe) static var debugShowsSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Glassine").font(.title2.weight(.semibold))
                    Text("Glassine runs quietly in the background. Use these shortcuts:")
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                shortcutRow("Capture area", .captureArea)
                shortcutRow("Capture window", .captureWindow)
                shortcutRow("Capture screen", .captureScreen)
                shortcutRow("Copy text from screen", .captureText)
                shortcutRow("Show/hide pins", .togglePins)
                shortcutRow("Open settings", .openSettings)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

            if hasAccess {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen Recording is on — you're all set").font(.headline)
                        Text("""
                        macOS may ask about once a month whether Glassine can keep accessing \
                        your screen. Every screenshot app gets this; choose Allow.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Allow Screen Recording", systemImage: "rectangle.dashed.badge.record")
                        .font(.headline)
                    Text("macOS asks every screenshot app for this. It takes three steps:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    PermissionStep(number: 1, isDone: prompted, text: prompted
                                   ? "macOS has asked once already — open System Settings with the button below."
                                   : "Click the button below. macOS asks — choose “Open System Settings”.")
                    PermissionStep(number: 2, isDone: false,
                                   text: "Turn on Glassine under Screen & System Audio Recording.")
                    PermissionStep(number: 3, isDone: false,
                                   text: "When macOS offers “Quit & Reopen”, click it. Glassine comes back ready.")
                    HStack {
                        Button(ScreenAccess.requestTitle) {
                            ScreenAccess.request()
                            prompted = ScreenAccess.hasPrompted
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                        Text("Everything stays on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            HStack {
                Button("Open Settings", action: openSettings)
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = ScreenAccess.isGranted && !Self.debugShowsSteps
        }
    }

    @ViewBuilder
    private func shortcutRow(_ title: String, _ name: KeyboardShortcuts.Name) -> some View {
        GridRow {
            Text(title)
            Text(KeyboardShortcuts.getShortcut(for: name)?.description ?? "Not set")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionStep: View {
    let number: Int
    let isDone: Bool
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ZStack {
                Circle().fill(isDone ? Color.green : Color.primary.opacity(0.12)).frame(width: 20, height: 20)
                if isDone {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.semibold))
                }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.callout)
                .foregroundStyle(isDone ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
