import Foundation

struct HandMotionSample: Codable, Sendable {
    let frame: Int
    let grip: Double
    let opacity: Double
    let pullProgress: Double
}

/// Контракт заменяемого визуала: изображения и позы подключаются через JSON.
struct HandAnimationDescriptor: Codable, Sendable {
    enum Renderer: String, Codable, Sendable { case pngSequence }
    var renderer: Renderer
    var frameNames: [String]
    var canvasWidth: Double
    var canvasHeight: Double
    var topBleedFraction: Double
    var duration: Double?
    var framesPerSecond: Double?
    var frameDirectory: String?
    var motionSamples: [HandMotionSample]?
    var gestureOpenFrame: Int?
    var gestureReadyFrame: Int?
    var pullStartFrame: Int?
    var pullEndFrame: Int?
    var releaseStartFrame: Int?
    var departureStartFrame: Int?
    var upwardPullPixels: Double?

    var frameCount: Int { frameNames.count }

    static let fallback = Self(renderer: .pngSequence, frameNames: [], canvasWidth: 512,
                               canvasHeight: 512, topBleedFraction: 0.04)
}
