// A neutral full-screen backdrop for recording README GIFs, so no real windows or
// messages end up in them. Run: swift Design/demo/DemoScene.swift   (quit: ⌘Q)
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct Scene: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.94, blue: 0.97), Color(red: 0.86, green: 0.88, blue: 0.94)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .top, spacing: 28) {
                article
                VStack(spacing: 20) {
                    stats
                    qrCard
                }
                .frame(width: 300)
            }
            .padding(48)
        }
    }

    private var article: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FIELD NOTES").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(.secondary)
            Text("Designing quiet tools").font(.system(size: 40, weight: .bold, design: .serif))
            Text("""
            The best utilities disappear until you need them. They live behind a shortcut, \
            do one thing quickly, and get out of the way again.
            """)
            .font(.system(size: 19))
            Text("""
            A screenshot tool is a good test: freeze the screen, pick an area, and the result \
            should already be where you want it — on the clipboard, in a chat, or pinned \
            next to the code you are writing.
            """)
            .font(.system(size: 17))
            .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(Array(zip(["Capture", "Annotate", "Pin", "Copy text"], [Color.blue, .orange, .pink, .green])), id: \.0) { title, color in
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                }
            }
            illustration
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    /// A colorful "photo" so captures and annotations have something to point at.
    private var illustration: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.93, green: 0.45, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.18)).frame(width: 260).offset(x: -180, y: 60)
            Circle().fill(.yellow.opacity(0.85)).frame(width: 90).offset(x: 160, y: -60)
            RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.9)).frame(width: 220, height: 64).offset(x: 40, y: 70)
                .overlay(Text("Glassine 0.1").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(.indigo).offset(x: 40, y: 70))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This week").font(.system(size: 15, weight: .semibold))
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array([0.45, 0.7, 0.55, 0.9, 0.65, 0.8, 0.5].enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .bottom, endPoint: .top))
                        .frame(width: 26, height: 140 * v)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("128 captures · 42 pins").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    private var qrCard: some View {
        VStack(spacing: 10) {
            Image(nsImage: Self.qr("https://example.com/glassine"))
                .interpolation(.none)
                .resizable()
                .frame(width: 150, height: 150)
            Text("Scan me").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    static func qr(_ text: String) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: image)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let frame = NSScreen.main!.visibleFrame
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua) // light cards and dark text in any system theme
    window.contentView = NSHostingView(rootView: Scene())
    window.setFrame(frame, display: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    let menu = NSMenu()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let appItem = NSMenuItem()
    appItem.submenu = appMenu
    menu.addItem(appItem)
    app.mainMenu = menu
    // Launched from a terminal, plain activation is declined; ask the frontmost app to hand over.
    if let frontmost = NSWorkspace.shared.frontmostApplication { NSRunningApplication.current.activate(from: frontmost) }
    app.run()
}
