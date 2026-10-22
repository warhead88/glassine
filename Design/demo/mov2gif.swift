// Converts a screen recording to a looping GIF for the README, with AVFoundation + ImageIO only.
//   swift Design/demo/mov2gif.swift <in.mov> <out.gif> [fps=12] [width=900]
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let fps = args.count > 3 ? Double(args[3])! : 12
let width = args.count > 4 ? Double(args[4])! : 900

let asset = AVURLAsset(url: input)
let duration = try await asset.load(.duration).seconds
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: width, height: 0)

let count = Int(duration * fps)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else {
    fatalError("can't write \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

for i in 0..<count {
    let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
    let (image, _) = try await generator.image(at: time)
    CGImageDestinationAddImage(destination, image, frameProperties)
}
guard CGImageDestinationFinalize(destination) else { fatalError("GIF encoding failed") }
let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("\(output.lastPathComponent): \(count) frames, \(size / 1024) KB")
