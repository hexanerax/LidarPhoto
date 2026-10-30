//
//  DepthPalette.swift
//  LidarPhoto
//

import Foundation

/// Gradients for shading the depth map, built from Apple's system colors.
/// Each runs from near (first stop) to far (last stop).
nonisolated enum DepthPalette: String, CaseIterable, Identifiable {
    case greyscale = "Greyscale"
    case greyscaleInverted = "Greyscale Inverted"
    case spectrum = "Spectrum"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case fire = "Fire"

    var id: String { rawValue }
    var isGreyscale: Bool { self == .greyscale || self == .greyscaleInverted }

    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    // iOS system colors (light appearance).
    private static let black: RGB = (0, 0, 0)
    private static let white: RGB = (255, 255, 255)
    private static let red: RGB = (255, 59, 48)
    private static let orange: RGB = (255, 149, 0)
    private static let yellow: RGB = (255, 204, 0)
    private static let green: RGB = (52, 199, 89)
    private static let mint: RGB = (0, 199, 190)
    private static let teal: RGB = (48, 176, 199)
    private static let cyan: RGB = (50, 173, 230)
    private static let blue: RGB = (0, 122, 255)
    private static let indigo: RGB = (88, 86, 214)
    private static let purple: RGB = (175, 82, 222)
    private static let pink: RGB = (255, 45, 85)

    private var stops: [RGB] {
        switch self {
        case .greyscale: [Self.black, Self.white]
        case .greyscaleInverted: [Self.white, Self.black]
        case .spectrum: [Self.red, Self.orange, Self.yellow, Self.green, Self.teal, Self.blue, Self.indigo]
        case .sunset: [Self.yellow, Self.orange, Self.pink, Self.purple, Self.indigo]
        case .ocean: [Self.mint, Self.cyan, Self.blue, Self.indigo]
        case .fire: [Self.yellow, Self.orange, Self.red, Self.black]
        }
    }

    /// 256-entry lookup table, index 0 = nearest, 255 = farthest.
    var lookupTable: [RGB] {
        let stops = stops
        return (0..<256).map { i in
            let position = Float(i) / 255 * Float(stops.count - 1)
            let lower = min(Int(position), stops.count - 2)
            let f = position - Float(lower)
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(Float(a) + (Float(b) - Float(a)) * f) }
            let a = stops[lower], b = stops[lower + 1]
            return (mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b))
        }
    }
}
