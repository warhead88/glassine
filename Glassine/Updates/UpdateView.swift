import AppKit
import SwiftUI

/// The update window: shown by a check (from Settings or the menu) and, without taking focus,
/// when the daily background check finds a release.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let model: UpdateModel
    private var window: NSWindow?

    init(model: UpdateModel) {
        self.model = model
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show(activate: Bool) {
        if window == nil {
            let controller = NSHostingController(rootView: UpdateView(model: model).themed())
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Software Update"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if activate {
            AppActivation.bringToFront()
            window?.makeKeyAndOrderFront(nil)
        }
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window answers like its secondary button.
        switch model.phase {
        case .checking, .downloading: model.send(.cancel)
        case .available, .ready: model.send(.later)
        case .upToDate, .failed: model.send(.done)
        case .preparing, .installing: break
        }
    }
}

struct UpdateView: View {
    let model: UpdateModel

    var body: some View {
        Group {
            switch model.phase {
            case .checking:
                StatusLayout(title: "Checking for updates…") {
                    ProgressView().controlSize(.small)
                } buttons: {
                    Button("Cancel") { model.send(.cancel) }.keyboardShortcut(.cancelAction)
                }
            case .upToDate:
                StatusLayout(title: "You're up to date", detail: "Glassine \(Updater.currentVersion) is the latest version.") {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } buttons: {
                    Button("OK") { model.send(.done) }.prominent().keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                StatusLayout(title: "Couldn't check for updates", detail: message) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } buttons: {
                    Button("OK") { model.send(.done) }.prominent().keyboardShortcut(.defaultAction)
                }
            default:
                if let release = model.release {
                    ReleaseLayout(release: release, phase: model.phase) { model.send($0) }
                }
            }
        }
        .frame(width: 480)
    }
}

private struct StatusLayout<Icon: View, Buttons: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let icon: Icon
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIcon(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        icon
                        Text(title).font(.headline)
                    }
                    if let detail {
                        Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                buttons
            }
            .controlSize(.large)
        }
        .padding(20)
    }
}

private struct ReleaseLayout: View {
    let release: UpdateModel.Release
    let phase: UpdateModel.Phase
    let send: (UpdateModel.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AppIcon(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glassine \(release.version) is available").font(.title3.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }

            if !release.notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(release.notes.enumerated()), id: \.offset) { _, section in
                            NotesSection(section: section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }

            footer.controlSize(.large)
        }
        .padding(20)
    }

    private var subtitle: String {
        var parts = ["You have \(Updater.currentVersion)"]
        if let size = release.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .available where release.infoURL != nil:
            HStack {
                Button("Skip This Version") { send(.skip) }
                Spacer()
                Button("Later") { send(.later) }.keyboardShortcut(.cancelAction)
                Button("Learn More") { send(.learnMore) }.prominent().keyboardShortcut(.defaultAction)
            }
        case .available:
            HStack {
                Button("Skip This Version") { send(.skip) }
                Spacer()
                Button("Later") { send(.later) }.keyboardShortcut(.cancelAction)
                Button("Update") { send(.install) }.prominent().keyboardShortcut(.defaultAction)
            }
        case .downloading(let received, let expected):
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let expected {
                        ProgressView(value: Double(min(received, expected)), total: Double(expected))
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(downloadText(received: received, expected: expected))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Cancel") { send(.cancel) }.keyboardShortcut(.cancelAction)
            }
        case .preparing, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phaseIsInstalling ? "Installing…" : "Preparing…").foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minHeight: 28)
        default: // .ready
            HStack {
                Text("Later installs it when you quit Glassine.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Later") { send(.later) }.keyboardShortcut(.cancelAction)
                Button("Install and Relaunch") { send(.install) }.prominent().keyboardShortcut(.defaultAction)
            }
        }
    }

    private var phaseIsInstalling: Bool {
        if case .installing = phase { true } else { false }
    }

    private func downloadText(received: UInt64, expected: UInt64?) -> String {
        let done = ByteCountFormatter.string(fromByteCount: Int64(received), countStyle: .file)
        guard let expected else { return "Downloading… \(done)" }
        return "Downloading… \(done) of \(ByteCountFormatter.string(fromByteCount: Int64(expected), countStyle: .file))"
    }
}

private struct NotesSection: View {
    let section: ReleaseNotes.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !section.title.isEmpty {
                Label(section.title, systemImage: style.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.color)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("•").foregroundStyle(.tertiary)
                    Text(Self.inlineMarkdown(item)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var style: (symbol: String, color: Color) {
        switch section.title.lowercased() {
        case "added", "new": ("plus.circle.fill", .green)
        case "fixed": ("wrench.and.screwdriver.fill", .orange)
        case "changed", "improved": ("arrow.triangle.2.circlepath.circle.fill", .blue)
        case "removed": ("minus.circle.fill", .red)
        case "security": ("lock.fill", .purple)
        default: ("circle.fill", .secondary)
        }
    }

    /// **Bold**, `code` and links in an item; plain text if it isn't valid Markdown.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct AppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
    }
}

@MainActor
private extension Button {
    /// The window's main button: Liquid Glass on macOS 26+.
    @ViewBuilder
    func prominent() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
