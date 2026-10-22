import AppKit

/// Short UI sounds that play on every trigger, however quickly they come.
///
/// `NSSound(named:)` hands out one shared instance per name, and `play()` does nothing while it
/// is still playing — so closing and immediately reopening area capture stayed silent. Glassine
/// keeps its own copies (so volume changes don't touch the shared one) and restarts them instead.
@MainActor
enum SoundEffects {
    private static var sounds: [String: NSSound] = [:]

    static func play(_ name: String, volume: Float = 1) {
        let sound = sounds[name] ?? {
            let copy = NSSound(named: name)?.copy() as? NSSound
            copy?.volume = volume
            sounds[name] = copy
            return copy
        }()
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
