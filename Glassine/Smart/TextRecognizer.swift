import CoreGraphics
import Vision

/// Recognizes text in an image, on device, with Vision. (QR codes are found separately, in every
/// capture's preview — see `BarcodeDetector`.)
enum TextRecognizer {
    /// The recognized text, lines in reading order; empty if there is none.
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["ru-RU", "en-US"]

            try VNImageRequestHandler(cgImage: image).perform([request])

            let fragments = (request.results ?? []).compactMap { observation -> TextLayout.Fragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                // Vision boxes have a bottom-left origin; flip to top-left for reading order.
                let box = observation.boundingBox
                return TextLayout.Fragment(text: candidate.string,
                                           box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            return TextLayout.join(fragments)
        }.value
    }
}
