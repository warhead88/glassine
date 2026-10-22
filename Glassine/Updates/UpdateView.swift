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
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .paper
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
                    Button("Cancel") { model.send(.cancel) }.buttonStyle(.paperSecondary).keyboardShortcut(.cancelAction)
                }
            case .upToDate:
                StatusLayout(title: "You're up to date", detail: "Glassine \(Updater.currentVersion) is the latest version.") {
                    CheckBadge(size: 20)
                } buttons: {
                    Button("OK") { model.send(.done) }.buttonStyle(.paperPrimary).keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                StatusLayout(title: "Couldn't check for updates", detail: message) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.ochre)
                } buttons: {
                    Button("OK") { model.send(.done) }.buttonStyle(.paperPrimary).keyboardShortcut(.defaultAction)
                }
            default:
                if let release = model.release {
                    ReleaseLayout(release: release, phase: model.phase) { model.send($0) }
                }
            }
        }
        .frame(width: 500)
        .background(Color.paper)
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
                AppIcon(size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        icon
                        Text(title)
                            .font(Font(Typography.fraunces(size: 22, weight: 460)))
                            .foregroundStyle(Color.ink)
                    }
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Spacer()
                buttons
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}

private struct ReleaseLayout: View {
    let release: UpdateModel.Release
    let phase: UpdateModel.Phase
    let send: (UpdateModel.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AppIcon(size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Glassine \(release.version) is here")
                        .textStyle(ThemeTokens.title)
                        .foregroundStyle(Color.ink)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.ink2)
                }
            }

            if !release.notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(release.notes.enumerated()), id: \.offset) { _, section in
                            NotesSection(section: section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.card, in: RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous).strokeBorder(Color.border))
            }

            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
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
            HStack(spacing: 10) {
                Button("Skip This Version") { send(.skip) }.buttonStyle(.paperQuiet)
                Spacer()
                Button("Later") { send(.later) }.buttonStyle(.paperSecondary).keyboardShortcut(.cancelAction)
                Button("Learn More") { send(.learnMore) }.buttonStyle(.paperPrimary).keyboardShortcut(.defaultAction)
            }
        case .available:
            HStack(spacing: 10) {
                Button("Skip This Version") { send(.skip) }.buttonStyle(.paperQuiet)
                Spacer()
                Button("Later") { send(.later) }.buttonStyle(.paperSecondary).keyboardShortcut(.cancelAction)
                Button("Update") { send(.install) }.buttonStyle(.paperPrimary).keyboardShortcut(.defaultAction)
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
                        .font(.system(size: 12)).foregroundStyle(Color.ink2).monospacedDigit()
                }
                Button("Cancel") { send(.cancel) }.buttonStyle(.paperSecondary).keyboardShortcut(.cancelAction)
            }
        case .preparing, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phaseIsInstalling ? "Installing…" : "Preparing…").font(.system(size: 13)).foregroundStyle(Color.ink2)
                Spacer()
            }
            .frame(minHeight: 28)
        default: // .ready
            HStack(spacing: 10) {
                Text("Later installs it when you quit Glassine.").font(.system(size: 12)).foregroundStyle(Color.ink2)
                Spacer()
                Button("Later") { send(.later) }.buttonStyle(.paperSecondary).keyboardShortcut(.cancelAction)
                Button("Install and Relaunch") { send(.install) }.buttonStyle(.paperPrimary).keyboardShortcut(.defaultAction)
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
        VStack(alignment: .leading, spacing: 8) {
            if !section.title.isEmpty {
                // A tag like a rubber stamp: small caps in a ruled box.
                Text(section.title)
                    .textStyle(ThemeTokens.label)
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1.2))
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("–").foregroundStyle(Color.ink3)
                    Text(Self.inlineMarkdown(item))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Added is sage (done), Changed is the stamp blue, Fixed ochre; red stays for recording.
    private var color: Color {
        switch section.title.lowercased() {
        case "added", "new": .sageDeep
        case "changed", "improved": .stamp
        case "fixed": .ochre
        default: .ink2
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
