import Foundation

/// What changed in a release, as shown in the update window. The appcast carries the release's
/// section of CHANGELOG.md (Keep a Changelog style) as plain text:
///
///     ### Added
///     - Screen recording
///     ### Fixed
///     - The start sound on quick reopen
enum ReleaseNotes {
    struct Section: Equatable {
        /// "Added", "Fixed", …; empty for lines before the first heading.
        var title: String
        var items: [String]
    }

    static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        var afterBlank = true
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            defer { afterBlank = line.isEmpty }
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                sections.append(Section(title: title, items: []))
                continue
            }
            if sections.isEmpty { sections.append(Section(title: "", items: [])) }
            let last = sections.count - 1
            if let bullet = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                sections[last].items.append(String(line.dropFirst(bullet.count)))
            } else if !afterBlank, let item = sections[last].items.indices.last {
                // A wrapped line continues the item or paragraph above it.
                sections[last].items[item] += " " + line
            } else {
                sections[last].items.append(line)
            }
        }
        return sections.filter { !$0.items.isEmpty }
    }
}
