import Testing
@testable import Glassine

@Suite("Release notes")
struct ReleaseNotesTests {
    typealias Section = ReleaseNotes.Section

    @Test func changelogSections() {
        let text = """
        ### Added
        - Screen recording
        - GIF export

        ### Fixed
        * The start sound
        """
        #expect(ReleaseNotes.parse(text) == [
            Section(title: "Added", items: ["Screen recording", "GIF export"]),
            Section(title: "Fixed", items: ["The start sound"]),
        ])
    }

    @Test func wrappedLinesJoinTheirItem() {
        let text = """
        ### Changed
        - A long item that
          wraps onto a second line
        - Next
        """
        #expect(ReleaseNotes.parse(text) == [Section(title: "Changed", items: ["A long item that wraps onto a second line", "Next"])])
    }

    @Test func plainParagraphsWithoutHeading() {
        let text = """
        First release: capture,
        the editor and pins.

        Thanks for trying it.
        """
        #expect(ReleaseNotes.parse(text) == [
            Section(title: "", items: ["First release: capture, the editor and pins.", "Thanks for trying it."]),
        ])
    }

    @Test func emptyHeadingsAreDropped() {
        #expect(ReleaseNotes.parse("### Removed\n\n### Fixed\n- Crash") == [Section(title: "Fixed", items: ["Crash"])])
        #expect(ReleaseNotes.parse("").isEmpty)
    }
}
