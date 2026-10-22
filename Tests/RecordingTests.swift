import CoreGraphics
import Foundation
import Testing
@testable import Glassine

@Suite("Recording")
struct RecordingTests {
    @Test func encoderSizeIsEvenPixels() {
        let size = RecordingMath.pixelSize(points: CGSize(width: 300.5, height: 201), scale: 2)
        #expect(size.width == 600 && size.height == 402)
        let odd = RecordingMath.pixelSize(points: CGSize(width: 301, height: 151), scale: 1)
        #expect(odd.width == 300 && odd.height == 150)
        let tiny = RecordingMath.pixelSize(points: CGSize(width: 0.4, height: 1), scale: 1)
        #expect(tiny.width == 2 && tiny.height == 2)
    }

    @Test func automaticBitrate() {
        // 1080p60 H.264 ≈ 12.4 Mbit/s; HEVC 30% less.
        #expect(RecordingMath.bitrate(width: 1920, height: 1080, fps: 60, codec: .h264, mbps: 0) == 12_441_600)
        #expect(RecordingMath.bitrate(width: 1920, height: 1080, fps: 60, codec: .hevc, mbps: 0) == 8_709_120)
        // Small areas get a floor, 5K at 60 fps a ceiling.
        #expect(RecordingMath.bitrate(width: 200, height: 200, fps: 30, codec: .h264, mbps: 0) == 2_000_000)
        #expect(RecordingMath.bitrate(width: 5120, height: 2880, fps: 60, codec: .h264, mbps: 0) == 80_000_000)
    }

    @Test func chosenBitrateWins() {
        #expect(RecordingMath.bitrate(width: 1920, height: 1080, fps: 60, codec: .hevc, mbps: 16) == 16_000_000)
    }

    @Test func gifIsScaledDownNeverUp() {
        #expect(RecordingMath.gifSize(width: 1600, height: 900, maxWidth: 800) == CGSize(width: 800, height: 450))
        #expect(RecordingMath.gifSize(width: 600, height: 400, maxWidth: 800) == CGSize(width: 600, height: 400))
        #expect(RecordingMath.gifSize(width: 1600, height: 900, maxWidth: 0) == CGSize(width: 1600, height: 900))
    }

    @Test func gifFrameTimes() {
        #expect(RecordingMath.gifFrameTimes(duration: 1, fps: 4) == [0, 0.25, 0.5, 0.75])
        #expect(RecordingMath.gifFrameTimes(duration: 0.01, fps: 15) == [0])
    }

    @Test func summaryForThePreview() {
        #expect(RecordingMath.summary(format: .video, codec: .h264, tracks: 2) == "MP4 · 2 tracks")
        #expect(RecordingMath.summary(format: .video, codec: .hevc, tracks: 1) == "MP4 · 1 track")
        #expect(RecordingMath.summary(format: .video, codec: .prores, tracks: 0) == "MOV · ProRes")
        #expect(RecordingMath.summary(format: .gif, codec: .h264, tracks: 2) == "GIF")
    }

    @Test func clock() {
        #expect(RecordingMath.clock(7.9) == "0:07")
        #expect(RecordingMath.clock(65) == "1:05")
        #expect(RecordingMath.clock(3909) == "1:05:09")
    }

    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let column = CGSize(width: 90, height: 420)
    let row = CGSize(width: 560, height: 70)

    @Test func controlsGoBesideTheAreaWhenTheyFit() {
        let area = CGRect(x: 400, y: 300, width: 400, height: 300)
        #expect(RecordingPanelLayout.besideArea(size: column, area: area, visible: visible, side: .right)
            == CGPoint(x: 812, y: 240))
        #expect(RecordingPanelLayout.besideArea(size: column, area: area, visible: visible, side: .left)
            == CGPoint(x: 298, y: 240))
        #expect(RecordingPanelLayout.besideArea(size: row, area: area, visible: visible, side: .below)
            == CGPoint(x: 320, y: 218))
        #expect(RecordingPanelLayout.besideArea(size: row, area: area, visible: visible, side: .above)
            == CGPoint(x: 320, y: 612))
    }

    @Test func controlsDockWhenTheAreaLeavesNoRoom() {
        // The whole screen: no side has room.
        for side in PanelSide.allCases {
            let size = side.isVertical ? column : row
            #expect(RecordingPanelLayout.besideArea(size: size, area: visible, visible: visible, side: side) == nil)
        }
        #expect(RecordingPanelLayout.docked(size: column, visible: visible, side: .right) == CGPoint(x: 1422, y: 265))
        #expect(RecordingPanelLayout.docked(size: row, visible: visible, side: .below) == CGPoint(x: 476, y: 0))
    }

    @Test func besideAWindowNearTheEdgeTheColumnStaysOnScreen() {
        let window = CGRect(x: 1000, y: 0, width: 300, height: 200)
        let origin = RecordingPanelLayout.besideArea(size: column, area: window, visible: visible, side: .right)
        #expect(origin?.y == 8) // pushed up from the bottom edge, not cut off
    }

    @Test func dockedShapeFlaresIntoTheEdge() {
        let path = PanelShape.rightEdgePath(thickness: 80, length: 400, radius: 20, shoulder: 16)
        #expect(path.contains(CGPoint(x: 79, y: 8)))     // the shoulder reaches into the edge
        #expect(!path.contains(CGPoint(x: 70, y: 2)))    // and curves away from it
        #expect(path.contains(CGPoint(x: 2, y: 200)))    // the body spans the full thickness
        #expect(!path.contains(CGPoint(x: 2, y: 18)))    // with a rounded outer corner
        let box = path.boundingBoxOfPath
        #expect(abs(box.minX) < 0.01 && abs(box.minY) < 0.01 && abs(box.width - 80) < 0.01 && abs(box.height - 400) < 0.01)
    }
}

@Suite("Audio tracks")
struct AudioTrackTests {
    let mic = AudioSource.microphone(id: "built-in", name: "MacBook Pro Microphone")
    let safari = AudioSource.app(bundleID: "com.apple.Safari", name: "Safari")
    let music = AudioSource.app(bundleID: "com.apple.Music", name: "Music")

    @Test func eachSourceIsCapturedOnceAndMixedIntoItsTrack() {
        let tracks = [AudioTrack(sources: [.system, mic]), AudioTrack(), AudioTrack(sources: [safari, music])]
        #expect(AudioTrackPlan.sources(of: tracks) == [.system, mic, safari, music])
        // The empty track gets no file track.
        #expect(AudioTrackPlan.mix(tracks) == [[0, 1], [2, 3]])
    }

    @Test func aSourceBelongsToOneTrack() {
        let tracks = [AudioTrack(sources: [.system]), AudioTrack(sources: [safari])]
        #expect(AudioTrackPlan.available([.system, mic, safari, music], in: tracks) == [mic, music])
    }

    @Test func unavailableSourcesAreDropped() {
        let tracks = [AudioTrack(sources: [.system, mic]), AudioTrack(sources: [mic])]
        let without = AudioTrackPlan.removing(\.isMicrophone, from: tracks)
        #expect(without.map(\.sources) == [[.system], []])
        #expect(AudioTrackPlan.mix(without) == [[0]])
    }

    @Test func onlyAppsThatArentRunningAreMissing() {
        // Music runs with its window on another Space: it is running, so it stays.
        let tracks = [AudioTrack(sources: [music, mic]), AudioTrack(sources: [.system, safari])]
        let missing = AudioTrackPlan.missingApps(in: tracks, running: ["com.apple.Music", "com.apple.finder"])
        #expect(missing == [safari])
        #expect(AudioTrackPlan.removing(missing.contains, from: tracks).map(\.sources) == [[music, mic], [.system]])
    }

    @Test func trackNamesSaySourcesWhenFew() {
        #expect(AudioTrackPlan.name(of: AudioTrack(sources: [.system, mic]), number: 1) == "System audio + MacBook Pro Microphone")
        #expect(AudioTrackPlan.name(of: AudioTrack(sources: [.system, mic, safari]), number: 2) == "Track 2")
    }

    @Test func tracksSurviveSaving() throws {
        let tracks = [AudioTrack(sources: [.system, mic]), AudioTrack(sources: [safari])]
        let decoded = try JSONDecoder().decode([AudioTrack].self, from: JSONEncoder().encode(tracks))
        #expect(decoded == tracks)
    }

    @Test func gifsHaveNoSound() {
        var options = RecordingOptions()
        options.audioTracks = [AudioTrack(sources: [.system])]
        #expect(options.recordedTracks.count == 1)
        options.format = .gif
        #expect(options.recordedTracks.isEmpty)
    }

    @Test func proResGoesInAMovie() {
        var options = RecordingOptions()
        #expect(options.fileExtension == "mp4")
        options.codec = .prores
        #expect(options.fileExtension == "mov" && !options.codec.hasBitrate)
        options.format = .gif
        #expect(options.fileExtension == "gif")
    }
}

@Suite("Moving and zooming the recorded area")
struct RecordingAreaTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let area = CGRect(x: 400, y: 300, width: 400, height: 300) // 4:3

    @Test func cornerResizeKeepsTheAspectAndTheOppositeCorner() {
        let bigger = SelectionGeometry.resizedKeepingAspect(area, handle: .bottomRight, dx: 80, in: screen, minWidth: 64)
        #expect(bigger == CGRect(x: 400, y: 300, width: 480, height: 360))
        let smaller = SelectionGeometry.resizedKeepingAspect(area, handle: .topLeft, dx: 100, in: screen, minWidth: 64)
        #expect(smaller == CGRect(x: 500, y: 375, width: 300, height: 225)) // bottom-right corner stayed at (800, 600)
    }

    @Test func zoomStopsAtTheScreenEdgeAndAtTheMinimum() {
        // Growing up-left from (800, 600): 600 pt of height left → at most 800 wide at 4:3.
        let huge = SelectionGeometry.resizedKeepingAspect(area, handle: .topLeft, dx: -2000, in: screen, minWidth: 64)
        #expect(huge.width == 800 && huge.height == 600 && huge.minY == 0)
        let tiny = SelectionGeometry.resizedKeepingAspect(area, handle: .bottomLeft, dx: 2000, in: screen, minWidth: 64)
        #expect(tiny.width == 64 && tiny.height == 48 && tiny.maxX == 800 && tiny.minY == 300)
    }

    @Test func edgeHandlesDontZoom() {
        #expect(SelectionGeometry.resizedKeepingAspect(area, handle: .right, dx: 50, in: screen, minWidth: 64) == area)
    }

    @Test func theBorderCanBeGrabbedOnEitherSide() {
        #expect(SelectionGeometry.isOnBorder(CGPoint(x: 398, y: 450), of: area))
        #expect(SelectionGeometry.isOnBorder(CGPoint(x: 600, y: 304), of: area))
        #expect(!SelectionGeometry.isOnBorder(CGPoint(x: 600, y: 450), of: area)) // inside: the app's
        #expect(!SelectionGeometry.isOnBorder(CGPoint(x: 380, y: 450), of: area))
    }

    @Test func freeResizeStaysOnScreenAndUsable() {
        let shrunk = SelectionGeometry.limited(CGRect(x: 10, y: 10, width: 5, height: 5), in: screen,
                                               minSize: CGSize(width: 64, height: 48))
        #expect(shrunk.size == CGSize(width: 64, height: 48))
        let past = SelectionGeometry.limited(CGRect(x: 1400, y: 900, width: 300, height: 200), in: screen,
                                             minSize: CGSize(width: 64, height: 48))
        #expect(screen.contains(past))
    }

    @Test func screenCoordinatesRoundTrip() {
        let frame = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let local = CGRect(x: 100, y: 50, width: 640, height: 360)
        let global = ScreenGeometry.globalCocoa(fromLocalFlipped: local, screenFrame: frame)
        #expect(ScreenGeometry.localFlipped(fromGlobalCocoa: global, screenFrame: frame) == local)
    }
}
