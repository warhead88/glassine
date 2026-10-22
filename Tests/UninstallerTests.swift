import Foundation
import Testing
@testable import Glassine

@Suite("Uninstaller")
@MainActor
struct UninstallerTests {
    let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
    var owned: [URL] {
        ["Library/Caches/com.warhead88.glassine", "Library/Preferences/com.warhead88.glassine.plist",
         "Library/Logs/com.warhead88.glassine"].map { home.appending(path: $0) }
    }

    @Test func trashesOnlyWhatExistsWithTheAppLast() {
        let app = URL(filePath: "/Applications/Glassine.app")
        let existing = Set([owned[0], owned[1], app])
        let plan = Uninstaller.plan(owned: owned, appBundle: app, exists: { existing.contains($0) })
        #expect(plan.trash == [owned[0], owned[1], app])
    }

    @Test func neverTrashesABuildTheAppRunsFrom() {
        let build = URL(filePath: "/Users/someone/Code/ScreenShots/build.noindex/Build/Products/Debug/Glassine.app")
        let plan = Uninstaller.plan(owned: owned, appBundle: build, exists: { _ in true })
        #expect(!plan.trash.contains(build))
    }

    @Test func screenshotsOnlyWhenAskedAndFromTheDefaultFolder() {
        let pictures = home.appending(path: "Pictures/Glassine", directoryHint: .isDirectory)
        let desktop = home.appending(path: "Desktop", directoryHint: .isDirectory)
        #expect(Uninstaller.removableScreenshotFolder(saveFolder: pictures, defaultFolder: pictures) == pictures)
        #expect(Uninstaller.removableScreenshotFolder(saveFolder: desktop, defaultFolder: pictures) == nil)

        let without = Uninstaller.plan(owned: owned, appBundle: URL(filePath: "/Applications/Glassine.app"), exists: { _ in true })
        #expect(!without.trash.contains(pictures))
        let with = Uninstaller.plan(owned: owned, appBundle: URL(filePath: "/Applications/Glassine.app"),
                                    screenshots: pictures, exists: { _ in true })
        #expect(with.trash.contains(pictures))
        #expect(with.trash.last == URL(filePath: "/Applications/Glassine.app"))
    }

    @Test func ownedPathsAreAllNamedAfterTheBundle() {
        for url in AppPaths.owned {
            #expect(url.path.contains("com.warhead88.glassine"))
        }
    }
}
