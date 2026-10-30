//
//  DepthColorizer.swift
//  LidarPhoto
//

import AVFoundation
import UIKit

/// Turns an `AVDepthData` frame into an image shaded with a `DepthPalette` (near = first stop).
/// Greyscale produces a true single-channel image; other palettes produce RGB.
nonisolated enum DepthRenderer {
    /// Default depth range (meters) mapped onto the gradient: the scanner's rated range.
    static let defaultRange: ClosedRange<Float> = 0.2...5.0

    static func image(from depthData: AVDepthData, palette: DepthPalette, range: ClosedRange<Float>) -> UIImage? {
        let nearMeters = range.lowerBound, farMeters = range.upperBound
        let float32 = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = float32.depthDataMap

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)

        let grey = palette.isGreyscale
        let channels = grey ? 1 : 4
        let table = palette.lookupTable
        var pixels = [UInt8](repeating: 0, count: width * height * channels)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let depth = row[x]
                guard depth.isFinite, depth > 0 else { continue } // invalid depth stays black
                let t = min(max((depth - nearMeters) / (farMeters - nearMeters), 0), 1)
                let color = table[Int(t * 255)]
                let o = (y * width + x) * channels
                if grey {
                    pixels[o] = color.r
                } else {
                    pixels[o] = color.r
                    pixels[o + 1] = color.g
                    pixels[o + 2] = color.b
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: channels * 8,
                bytesPerRow: width * channels,
                space: grey ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: grey ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }

        // Depth buffers arrive in the sensor's landscape orientation.
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }
}
