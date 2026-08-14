import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: VideoFrameExtractor.swift <video> <output-directory>")
}

let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let asset = AVURLAsset(url: videoURL)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let frameTimes: [Double] = [4, 9, 17, 22, 27, 35, 42, 49, 53, 59, 68, 76]

for (index, seconds) in frameTimes.enumerated() {
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    let image = try generator.copyCGImage(at: time, actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        continue
    }

    let filename = String(format: "frame-%02d-%02.0fs.png", index + 1, seconds)
    try data.write(to: outputDirectory.appendingPathComponent(filename))
}
