import KeyboardShortcuts
import SwiftUI

/// Shown on first launch and whenever a capture is attempted without Screen Recording access.
struct WelcomeView: View {
    var openSettings: () -> Void
    var close: () -> Void

    @State private var hasAccess = ScreenAccess.isGranted

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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Screen Recording", systemImage: "rectangle.dashed.badge.record")
                        .font(.headline)
                    Spacer()
                    if hasAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…", action: ScreenAccess.request)
                    }
                }
                Text("""
                macOS requires this permission for any app that takes screenshots. \
                Everything stays on your Mac — Glassine never uses the network.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("""
                macOS may ask again about once a month whether Glassine can keep \
                accessing your screen. This happens to every screenshot app; choose Allow.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
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
            hasAccess = ScreenAccess.isGranted
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
