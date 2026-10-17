import Foundation

struct HandPullConfiguration: Sendable {
    var topRearmThreshold = 12.0
    var playbackDuration = 3.0
    var frameCount = 45
    var surfaceHeight = 166.0
    // Replay и жест раскрывают одну и ту же свободную область.
    var refreshThreshold: Double { surfaceHeight }
    var pullCancellationDuration = 0.24
    var motionSamples: [HandMotionSample] = []
    var gestureOpenProgress = 0.30
    var gestureReadyProgress = 0.46
    var pullStartProgress = 0.52
    var releaseStartProgress = 0.90
    var departureStartProgress = 0.90
    var hasRenderedTimeline: Bool { !motionSamples.isEmpty }

    mutating func use(_ descriptor: HandAnimationDescriptor) {
        frameCount = descriptor.frameCount
        playbackDuration = descriptor.duration ?? playbackDuration
        motionSamples = descriptor.motionSamples ?? []
        guard hasRenderedTimeline, frameCount > 0 else { return }
        let count = Double(frameCount)
        gestureOpenProgress = Double(descriptor.gestureOpenFrame ?? 48) / count
        gestureReadyProgress = Double(descriptor.gestureReadyFrame ?? 72) / count
        pullStartProgress = Double(descriptor.pullStartFrame ?? 75) / count
        releaseStartProgress = Double(descriptor.releaseStartFrame ?? 112) / count
        departureStartProgress = Double(descriptor.departureStartFrame ?? 126) / count
    }

    func catalogReturnFraction(_ progress: Double) -> Double {
        guard hasRenderedTimeline else { return HandPullTimeline.catalogReturnFraction(progress) }
        let position = min(Double(motionSamples.count - 1), max(0, progress * Double(frameCount)))
        let lower = Int(position), upper = min(motionSamples.count - 1, lower + 1)
        let blend = position - Double(lower)
        return motionSamples[lower].pullProgress * (1 - blend) + motionSamples[upper].pullProgress * blend
    }

    func surfaceFraction(_ progress: Double) -> Double {
        guard hasRenderedTimeline else { return HandPullTimeline.surfaceFraction(progress) }
        // Полная свободная область нужна уже к окончанию появления (0.3 s),
        // иначе нижняя маска срезает пальцы во время последующего опускания.
        let openingProgress = min(gestureOpenProgress, 0.3 / playbackDuration)
        return HandPullTimeline.smooth(progress / openingProgress) * (1 - catalogReturnFraction(progress))
    }

    func phase(at progress: Double) -> HandPullPhase {
        guard hasRenderedTimeline else { return HandPullTimeline.phase(progress: progress) }
        if progress < gestureOpenProgress { return .appearing }
        if progress < pullStartProgress { return .gripping }
        if progress < releaseStartProgress { return .returning }
        return .disappearing
    }
}

enum HandPullPhase: String {
    case idle, appearing, gripping, returning, disappearing
}

/// Чистые функции: время, поза и движение интерфейса используют один прогресс.
enum HandPullTimeline {
    static func progress(elapsed: Double, duration: Double) -> Double {
        guard duration > 0, duration.isFinite else { return 1 }
        guard elapsed.isFinite else { return elapsed == .infinity ? 1 : 0 }
        return min(1, max(0, elapsed / duration))
    }

    static func frameIndex(progress: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let p = progress.isNaN ? 0 : min(1, max(0, progress))
        return min(count - 1, Int(floor(p * Double(count))))
    }

    static func phase(progress: Double) -> HandPullPhase {
        switch progress {
        case ..<0.30: .appearing
        case ..<0.52: .gripping
        case ..<0.90: .returning
        default: .disappearing
        }
    }

    static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    /// Сначала рука натягивает ткань, затем вслед за ней возвращается каталог.
    static func catalogReturnFraction(_ progress: Double) -> Double {
        let t = min(1, max(0, (progress - 0.64) / 0.26))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    static func surfaceFraction(_ progress: Double) -> Double {
        smooth(progress / 0.26) * (1 - catalogReturnFraction(progress))
    }
}
