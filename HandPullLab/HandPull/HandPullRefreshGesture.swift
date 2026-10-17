import Foundation

/// Чистое состояние одного pull-to-refresh. Пик натяжения не заменяет текущую
/// величину: пользователь может вернуть палец назад и отменить готовый хват.
struct HandPullRefreshGesture {
    let threshold: Double
    let topTolerance: Double
    let openProgress: Double
    let readyProgress: Double
    private(set) var isActive = false
    private(set) var isEligible = false
    private(set) var distance = 0.0
    var isReady: Bool { isActive && isEligible && distance >= threshold }
    // Открытая кисть до упора; только на упоре начинается сжатие.
    var progress: Double { isReady ? readyProgress : openProgress * HandPullTimeline.smooth(distance / threshold) }

    init(threshold: Double = 96, topTolerance: Double = 12,
         openProgress: Double = 0.30, readyProgress: Double = 0.46) {
        self.threshold = max(1, threshold)
        self.topTolerance = topTolerance
        self.openProgress = openProgress
        self.readyProgress = readyProgress
    }

    mutating func begin(at normalizedOffset: Double) {
        isActive = true
        isEligible = abs(normalizedOffset) <= topTolerance
        distance = 0
    }

    mutating func update(normalizedOffset: Double, programmatic: Bool = false) {
        guard isActive, isEligible, !programmatic else { return }
        distance = normalizedOffset.isFinite ? min(threshold, max(0, -normalizedOffset)) : 0
    }

    mutating func cancel() {
        isActive = false
        isEligible = false
        distance = 0
    }
}
