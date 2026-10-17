import SwiftUI
import QuartzCore

@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var owner: HandPullController?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(timestamp: link.timestamp) }
}

@MainActor
@Observable
final class HandPullController {
    let configuration: HandPullConfiguration
    private(set) var refreshGesture: HandPullRefreshGesture
    private(set) var phase: HandPullPhase = .idle
    private(set) var progress = 0.0
    private(set) var motionTime = 0.0
    private(set) var frameIndex = 0
    private(set) var isPlaying = false
    private(set) var isProgrammaticScroll = false
    private(set) var isPreviewing = false
    private(set) var catalogOffset = 0.0
    private(set) var enabled = true
    private(set) var reduceMotion = false
    private(set) var refreshCount = 0
    var isUserInteracting: Bool { refreshGesture.isActive }
    var isPulling: Bool { refreshGesture.isActive && refreshGesture.distance > 0 && enabled && !reduceMotion }
    var showsOverlay: Bool { isPlaying || isPreviewing || isPulling }
    var isCancelling: Bool { playbackStyle == .cancellation && isPlaying }

    var surfaceHeight: Double {
        guard isPlaying else { return 0 }
        switch playbackStyle {
        case .demo:
            return (configuration.surfaceHeight + startingOffset) * configuration.surfaceFraction(progress)
        case .completion:
            return startingSurfaceHeight * (1 - configuration.catalogReturnFraction(progress))
        case .cancellation:
            return startingSurfaceHeight * (1 - HandPullTimeline.smooth(playbackFraction))
        case .none: return 0
        }
    }

    var neutralHeight: Double {
        if isPulling { return refreshGesture.distance }
        if playbackStyle == .demo { return configuration.surfaceHeight * configuration.surfaceFraction(progress) }
        return surfaceHeight
    }

    /// Общий сдвиг готового холста: его тяга адаптируется к величине жеста,
    /// без изменения формы руки и без движения картинки поверх неподвижного списка.
    func renderedSceneAdjustment(renderedPullHeight: Double) -> Double {
        guard configuration.hasRenderedTimeline, !isPreviewing else { return 0 }
        if isPulling { return refreshGesture.distance - configuration.surfaceHeight }
        let height = playbackStyle == .demo ? configuration.surfaceHeight : startingSurfaceHeight
        return height - configuration.surfaceHeight -
            (height - renderedPullHeight) * configuration.catalogReturnFraction(progress)
    }

    var refreshStatus: String {
        if isCancelling { return "Жест отменён" }
        if isPlaying { return "Обновляем меню…" }
        if refreshGesture.isReady { return "Отпустите для обновления" }
        if isPulling { return "Потяните ещё немного" }
        return refreshCount > 0 ? "Меню обновлено" : "Потяните вниз в начале списка"
    }

    var accessibilityStatus: String {
        if isCancelling { return "cancelling" }
        if isPlaying { return "refreshing" }
        if refreshGesture.isReady { return "ready" }
        if isPulling { return "pulling" }
        return refreshCount > 0 ? "updated" : "idle"
    }

    private enum PlaybackStyle { case none, demo, completion, cancellation }
    private var playbackStyle: PlaybackStyle = .none
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var linkTarget: DisplayLinkTarget?
    @ObservationIgnored private var startTime = 0.0
    @ObservationIgnored private var startingOffset = 0.0
    @ObservationIgnored private var startingProgress = 0.0
    @ObservationIgnored private var startingSurfaceHeight = 0.0
    @ObservationIgnored private var playbackDuration = 0.0
    @ObservationIgnored private var moveScroll: ((Double) -> Void)?
    @ObservationIgnored private var followTarget = 0.0
    @ObservationIgnored private var lastFollowTime = 0.0
    @ObservationIgnored private var playbackMotionStart = 0.0
    private var playbackFraction = 0.0

    init(configuration: HandPullConfiguration = .init()) {
        self.configuration = configuration
        refreshGesture = HandPullRefreshGesture(threshold: configuration.refreshThreshold,
                                                topTolerance: configuration.topRearmThreshold,
                                                openProgress: configuration.gestureOpenProgress,
                                                readyProgress: configuration.gestureReadyProgress)
    }

    func setPreferences(enabled: Bool, reduceMotion: Bool) {
        self.enabled = enabled
        self.reduceMotion = reduceMotion
        if !enabled || reduceMotion { cancel() }
    }

    func geometryChanged(offset: Double) {
        catalogOffset = max(0, offset)
        guard refreshGesture.isActive else { return }
        refreshGesture.update(normalizedOffset: offset, programmatic: isProgrammaticScroll)
        guard enabled, !reduceMotion else { return }
        followTarget = refreshGesture.progress
        if displayLink == nil, refreshGesture.distance > 0 {
            lastFollowTime = CACurrentMediaTime()
            startClock()
        }
    }

    func userGestureBegan(at offset: Double, framesReady: Bool = true) {
        cancel()
        catalogOffset = max(0, offset)
        guard enabled, framesReady else { return }
        refreshGesture.begin(at: offset)
    }

    /// Вызывается при отпускании пальца, до завершения нативного bounce.
    func userScrollEnded(at offset: Double, framesReady: Bool, move: @escaping (Double) -> Void) {
        guard refreshGesture.isActive else { return }
        refreshGesture.update(normalizedOffset: offset)
        let distance = refreshGesture.distance
        let ready = refreshGesture.isReady
        // Даже быстрый жест продолжаем с уже показанной позы. Подстановка
        // openProgress здесь перескакивала через появление и часть хвата.
        let releaseProgress = progress
        if reduceMotion {
            cancel()
            if ready && enabled { refreshWithoutMotion() }
            return
        }
        guard distance > 0, framesReady, enabled else { cancel(); return }
        start(style: ready ? .completion : .cancellation,
              progress: releaseProgress, distance: distance, move: move)
    }

    func replay(framesReady: Bool, move: @escaping (Double) -> Void) {
        guard !isPlaying, !isPulling, enabled, !reduceMotion, framesReady,
              configuration.playbackDuration > 0, configuration.frameCount > 0 else { return }
        start(style: .demo, progress: 0, distance: 0, move: move)
    }

    func refreshWithoutMotion() {
        cancel()
        refreshCount += 1
    }

    private func start(style: PlaybackStyle, progress initialProgress: Double,
                       distance: Double, move: @escaping (Double) -> Void) {
        let offset = catalogOffset
        let currentMotionTime = motionTime
        cancel()
        motionTime = currentMotionTime
        playbackMotionStart = currentMotionTime
        startingOffset = offset
        startingProgress = initialProgress
        playbackFraction = 0
        startingSurfaceHeight = distance
        moveScroll = move
        playbackStyle = style
        playbackDuration = style == .cancellation ? configuration.pullCancellationDuration :
            configuration.playbackDuration * (1 - initialProgress)
        updateVisual(progress: initialProgress)
        isPlaying = true
        if style != .demo {
            // Меняем нативный overscroll на равный отступ в одной транзакции.
            // Контент сохраняет положение под пальцем в момент отпускания.
            isProgrammaticScroll = true
            move(0)
        }
        startTime = CACurrentMediaTime()
        startClock()
    }

    private func startClock() {
        guard displayLink == nil else { return }
        let target = DisplayLinkTarget()
        target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        linkTarget = target
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func tick(timestamp: Double) {
        if isPlaying { apply(elapsed: timestamp - startTime) }
        else if refreshGesture.isActive {
            advanceFollow(by: max(0, timestamp - lastFollowTime))
            lastFollowTime = timestamp
        }
    }

    /// Один и тот же display link сглаживает жест и проигрывает завершение.
    /// Параметр времени позволяет проверить переход без sleep.
    func advanceFollow(by deltaTime: Double) {
        guard refreshGesture.isActive, !isPlaying, deltaTime.isFinite, deltaTime > 0 else { return }
        motionTime += deltaTime
        let next = progress + (followTarget - progress) * (1 - exp(-deltaTime / 0.065))
        updateVisual(progress: abs(followTarget - next) < 0.0001 ? followTarget : next)
    }

    func apply(elapsed: Double) {
        guard isPlaying else { return }
        let t = HandPullTimeline.progress(elapsed: elapsed, duration: playbackDuration)
        motionTime = playbackMotionStart + max(0, elapsed)
        playbackFraction = t
        let next = playbackStyle == .cancellation ? startingProgress * (1 - HandPullTimeline.smooth(t)) :
            startingProgress + (1 - startingProgress) * t
        updateVisual(progress: next)
        let fraction = configuration.catalogReturnFraction(progress)
        if playbackStyle == .demo, fraction > 0 {
            isProgrammaticScroll = true
            moveScroll?(startingOffset * (1 - fraction))
        }
        if t >= 1 {
            let didRefresh = playbackStyle != .cancellation
            cancel()
            if didRefresh { refreshCount += 1 }
        }
    }

    private func updateVisual(progress value: Double) {
        progress = min(1, max(0, value))
        frameIndex = HandPullTimeline.frameIndex(progress: progress, count: configuration.frameCount) ?? 0
        phase = progress > 0 ? configuration.phase(at: progress) : .idle
    }

    /// Отмена останавливает единственный источник времени и не сбрасывает новый цикл позже.
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        linkTarget = nil
        moveScroll = nil
        playbackStyle = .none
        phase = .idle
        progress = 0
        motionTime = 0
        frameIndex = 0
        isPlaying = false
        isPreviewing = false
        isProgrammaticScroll = false
        refreshGesture.cancel()
        followTarget = 0
        lastFollowTime = 0
    }

    func reset() {
        cancel()
        refreshCount = 0
    }

    func preview(progress: Double, framesReady: Bool) {
        cancel()
        guard framesReady, enabled, !reduceMotion else { return }
        updateVisual(progress: progress)
        isPreviewing = true
    }
}
