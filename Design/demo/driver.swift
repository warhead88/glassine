// Plays a scripted demo with synthetic mouse and keyboard input (needs Accessibility).
//   driver <script>   — one command per line:
//   wait <s> | move <x> <y> [s] | drag <x1> <y1> <x2> <y2> [s] | click <x> <y> | key <code> [cmd opt shift ctrl]
//   type <text> | scroll <x> <y> <lines>
//   driver --backup-clipboard <file> | --restore-clipboard <file>   — every item and type, images included
import AppKit

func post(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)?.post(tap: .cghidEventTap)
}

var cursor: CGPoint = {
    let m = NSEvent.mouseLocation
    return CGPoint(x: m.x, y: NSScreen.screens[0].frame.height - m.y)
}()

func glide(to target: CGPoint, seconds: Double, dragging: Bool) {
    let steps = max(Int(seconds * 60), 1)
    let start = cursor
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 // ease in-out
        let p = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
        post(dragging ? .leftMouseDragged : .mouseMoved, p)
        Thread.sleep(forTimeInterval: seconds / Double(steps))
    }
    cursor = target
}

func key(_ code: CGKeyCode, _ mods: [Substring]) {
    var flags: CGEventFlags = []
    for m in mods {
        switch m {
        case "cmd": flags.insert(.maskCommand)
        case "opt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        case "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
    }
}

func type(_ text: String) {
    for ch in text.utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            var c = ch
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.07)
    }
}

// Clipboard backup / restore, keeping every type of every item.
let args = CommandLine.arguments
if args.count == 3, args[1] == "--backup-clipboard" {
    let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t.rawValue, $0) } })
    }
    try! NSKeyedArchiver.archivedData(withRootObject: items, requiringSecureCoding: false).write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}
if args.count == 3, args[1] == "--restore-clipboard" {
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[2]))
    let items = (try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [[String: Data]]) ?? []
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(items.map { dict in
        let item = NSPasteboardItem()
        for (t, d) in dict { item.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        return item
    })
    exit(0)
}

for line in try! String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n") {
    let parts = line.split(separator: " ")
    guard let command = parts.first, !command.hasPrefix("#") else { continue }
    let n = parts.dropFirst().compactMap { Double($0) }
    switch command {
    case "wait": Thread.sleep(forTimeInterval: n[0])
    case "move": glide(to: CGPoint(x: n[0], y: n[1]), seconds: n.count > 2 ? n[2] : 0.6, dragging: false)
    case "drag":
        glide(to: CGPoint(x: n[0], y: n[1]), seconds: 0.4, dragging: false)
        post(.leftMouseDown, cursor)
        glide(to: CGPoint(x: n[2], y: n[3]), seconds: n.count > 4 ? n[4] : 0.8, dragging: true)
        post(.leftMouseUp, cursor)
    case "click":
        glide(to: CGPoint(x: n[0], y: n[1]), seconds: 0.5, dragging: false)
        post(.leftMouseDown, cursor); Thread.sleep(forTimeInterval: 0.06); post(.leftMouseUp, cursor)
    case "key": key(CGKeyCode(n[0]), Array(parts.dropFirst(2)))
    case "type": type(parts.dropFirst().joined(separator: " "))
    case "scroll":
        glide(to: CGPoint(x: n[0], y: n[1]), seconds: 0.3, dragging: false)
        for _ in 0..<Int(abs(n[2])) {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(n[2] > 0 ? 1 : -1), wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
        }
    default: print("unknown: \(line)")
    }
}
