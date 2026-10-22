import CoreGraphics
import Foundation
import Vision

/// Finds QR codes in a capture. Unlike text recognition this is a light request — about 10 ms
/// for a whole Retina screen — so it runs after every capture to offer "Copy QR Link".
enum BarcodeDetector {
    static func detect(_ image: CGImage) async -> [String] {
        await Task.detached(priority: .utility) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr, .microQR]
            guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
            let found = (request.results ?? []).compactMap { observation in
                observation.payloadStringValue.map { (payload: $0, box: observation.boundingBox) }
            }
            return ordered(found)
        }.value
    }

    /// Reading order — rows top to bottom, then left to right — without duplicates.
    /// Boxes are Vision's normalized rects (bottom-left origin).
    static func ordered(_ codes: [(payload: String, box: CGRect)]) -> [String] {
        let sorted = codes.sorted { a, b in
            // Same row when their vertical centers are closer than half the smaller height.
            if abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) / 2 {
                return a.box.minX < b.box.minX
            }
            return a.box.midY > b.box.midY
        }
        var seen = Set<String>()
        return sorted.map(\.payload).filter { seen.insert($0).inserted }
    }

    /// The payload as a web link, if it is one.
    static func link(_ payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }

    /// A short label for menus: the host and path for links, otherwise the start of the text.
    static func menuTitle(_ payload: String, limit: Int = 48) -> String {
        var text = payload
        if let url = link(payload) {
            text = (url.host ?? "") + url.path
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
