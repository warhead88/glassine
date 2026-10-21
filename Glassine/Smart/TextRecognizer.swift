import CoreGraphics
import Vision

/// Finds text and QR / barcodes in an image, on device, with Vision.
enum TextRecognizer {
    struct Result: Sendable {
        var text: String
        /// Payloads of QR codes and barcodes, in reading order.
        var codes: [String]

        var isEmpty: Bool { text.isEmpty && codes.isEmpty }
    }

    static func recognize(_ image: CGImage) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.automaticallyDetectsLanguage = true
            textRequest.recognitionLanguages = ["ru-RU", "en-US"]

            let codeRequest = VNDetectBarcodesRequest()

            try VNImageRequestHandler(cgImage: image).perform([textRequest, codeRequest])

            let fragments = (textRequest.results ?? []).compactMap { observation -> TextLayout.Fragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                // Vision boxes have a bottom-left origin; flip to top-left for reading order.
                let box = observation.boundingBox
                return TextLayout.Fragment(text: candidate.string,
                                           box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            let codes = (codeRequest.results ?? [])
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap(\.payloadStringValue)
            return Result(text: TextLayout.join(fragments), codes: Array(NSOrderedSet(array: codes)) as? [String] ?? codes)
        }.value
    }
}
