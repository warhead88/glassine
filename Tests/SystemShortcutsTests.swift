import Testing
@testable import Glassine

@Suite("macOS screenshot shortcuts")
struct SystemShortcutsTests {
    @Test func untouchedShortcutsCountAsOn() {
        #expect(SystemScreenshotShortcuts.enabledIDs([28, 30, 184], in: nil) == [28, 30, 184])
        #expect(SystemScreenshotShortcuts.enabledIDs([28, 30], in: [:]) == [28, 30])
    }

    @Test func turnedOffShortcutsAreSkipped() {
        let hotkeys: [String: Any] = [
            "28": ["enabled": 0],
            "30": ["enabled": false],
            "184": ["enabled": 1],
        ]
        #expect(SystemScreenshotShortcuts.enabledIDs([28, 30, 184], in: hotkeys) == [184])
    }

    @Test func defaultsAreTheScreenshotKeys() {
        let labels = SystemScreenshotShortcuts.all.map(\.label)
        #expect(labels == ["⇧⌘3", "⇧⌘4", "⇧⌘5"])
    }
}
