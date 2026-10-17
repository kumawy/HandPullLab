import XCTest
import UIKit
@testable import HandPullLab

final class PullGestureTests: XCTestCase {
    func testGraspStartsOnlyAtHardLimit() {
        var gesture = HandPullRefreshGesture()
        gesture.begin(at: 0)
        for distance in [1.0, 48, 84, 95.99] {
            gesture.update(normalizedOffset: -distance)
            XCTAssertFalse(gesture.isReady)
            XCTAssertLessThanOrEqual(gesture.progress, 0.30)
        }
        gesture.update(normalizedOffset: -96)
        XCTAssertTrue(gesture.isReady)
        XCTAssertEqual(gesture.progress, 0.46)
        gesture.update(normalizedOffset: -400)
        XCTAssertEqual(gesture.distance, 96)
        XCTAssertEqual(gesture.progress, 0.46)
    }

    func testFingerCanReverseAndDisarmBeforeRelease() {
        var gesture = HandPullRefreshGesture()
        gesture.begin(at: 0)
        gesture.update(normalizedOffset: -100)
        XCTAssertTrue(gesture.isReady)
        XCTAssertEqual(gesture.progress, 0.46)
        gesture.update(normalizedOffset: -24)
        XCTAssertFalse(gesture.isReady)
        XCTAssertLessThan(gesture.progress, 0.2)
        gesture.update(normalizedOffset: 0)
        XCTAssertEqual(gesture.progress, 0)
    }

    func testOnlyNewUserGestureAtTopCanPull() {
        var gesture = HandPullRefreshGesture()
        gesture.update(normalizedOffset: -200)
        XCTAssertEqual(gesture.progress, 0)
        gesture.begin(at: 240)
        gesture.update(normalizedOffset: -140)
        XCTAssertFalse(gesture.isReady)
        XCTAssertEqual(gesture.progress, 0)
        gesture.begin(at: 0)
        gesture.update(normalizedOffset: -140, programmatic: true)
        XCTAssertEqual(gesture.progress, 0)
        gesture.update(normalizedOffset: 115)
        XCTAssertEqual(gesture.progress, 0)
    }
}

@MainActor
final class PullToRefreshControllerTests: XCTestCase {
    func testFastReleaseContinuesFromTheActuallyDisplayedFrame() {
        let store = HandFrameStore()
        var configuration = HandPullConfiguration()
        configuration.use(store.descriptor)
        let controller = HandPullController(configuration: configuration)
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -1_000)
        controller.advanceFollow(by: 1.0 / 240)
        let displayedProgress = controller.progress
        let displayedFrame = controller.frameIndex
        controller.userScrollEnded(at: -1_000, framesReady: true) { _ in }
        XCTAssertEqual(controller.progress, displayedProgress)
        XCTAssertEqual(controller.frameIndex, displayedFrame,
                       "Быстрое отпускание не должно пропускать показанную фазу")
        controller.apply(elapsed: 3)
        XCTAssertEqual(controller.refreshCount, 1)
        XCTAssertFalse(controller.showsOverlay)
    }

    func testFullPullMatchesReplayAndReleaseKeepsTheSurfaceInPlace() {
        let store = HandFrameStore()
        var configuration = HandPullConfiguration()
        configuration.use(store.descriptor)
        let controller = HandPullController(configuration: configuration)
        controller.replay(framesReady: true) { _ in }
        controller.apply(elapsed: 72.0 / 60)
        let replayHeight = controller.neutralHeight
        let replayAdjustment = controller.renderedSceneAdjustment(renderedPullHeight: 62)
        controller.cancel()

        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -1_000)
        controller.advanceFollow(by: 1)
        XCTAssertEqual(controller.neutralHeight, replayHeight,
                       "Жест должен доходить до той же границы, что Replay")
        XCTAssertEqual(controller.renderedSceneAdjustment(renderedPullHeight: 62), replayAdjustment)
        let heldHeight = controller.neutralHeight
        let heldAdjustment = controller.renderedSceneAdjustment(renderedPullHeight: 62)
        controller.userScrollEnded(at: -1_000, framesReady: true) { _ in }
        XCTAssertEqual(controller.surfaceHeight, heldHeight)
        XCTAssertEqual(controller.renderedSceneAdjustment(renderedPullHeight: 62), heldAdjustment)
        controller.apply(elapsed: 0.25)
        XCTAssertLessThan(controller.surfaceHeight, heldHeight)
        controller.apply(elapsed: 2)
        XCTAssertEqual(controller.surfaceHeight, 0)
        XCTAssertEqual(controller.refreshCount, 1)
    }

    func testHandFollowsFingerWithoutScrollCommandsUntilRelease() {
        let controller = HandPullController()
        var positions: [Double] = []
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -40)
        controller.advanceFollow(by: 1)
        let halfProgress = controller.progress
        XCTAssertTrue(controller.isPulling)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.surfaceHeight, 0, "Нативный overscroll уже смещает каталог")
        controller.geometryChanged(offset: -200)
        controller.advanceFollow(by: 1)
        XCTAssertGreaterThan(controller.progress, halfProgress)
        XCTAssertEqual(controller.progress, 0.46)
        XCTAssertTrue(controller.refreshGesture.isReady)
        XCTAssertFalse(controller.isProgrammaticScroll)
        controller.userScrollEnded(at: -200, framesReady: true) { positions.append($0) }
        XCTAssertEqual(positions, [0])
        XCTAssertEqual(controller.surfaceHeight, 166, "Передаётся ограниченный overscroll")
        XCTAssertTrue(controller.isPlaying)
        controller.apply(elapsed: 1.7)
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertEqual(controller.surfaceHeight, 0)
        XCTAssertEqual(controller.refreshCount, 1)
        controller.geometryChanged(offset: -200)
        controller.userScrollEnded(at: -200, framesReady: true) { _ in XCTFail() }
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertEqual(controller.refreshCount, 1)
    }

    func testWeakPullReturnsWithoutRefreshAndNextPullWorks() {
        let controller = HandPullController()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -30)
        controller.userScrollEnded(at: -30, framesReady: true) { _ in }
        XCTAssertTrue(controller.isCancelling)
        controller.apply(elapsed: 0.3)
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertEqual(controller.refreshCount, 0)
        for expected in 1...2 {
            controller.userGestureBegan(at: 0)
            controller.geometryChanged(offset: -200)
            controller.userScrollEnded(at: -200, framesReady: true) { _ in }
            controller.apply(elapsed: 3)
            XCTAssertEqual(controller.refreshCount, expected)
        }
    }

    func testReturningFingerToTopBeforeReleaseDoesNotRefresh() {
        let controller = HandPullController()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -200)
        XCTAssertTrue(controller.refreshGesture.isReady)
        controller.userScrollEnded(at: 0, framesReady: true) { _ in XCTFail() }
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertEqual(controller.refreshCount, 0)
    }

    func testOrdinaryCatalogSwipeNeverStartsOldAutomaticEffect() {
        let controller = HandPullController()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: 115)
        controller.userScrollEnded(at: 115, framesReady: true) { _ in XCTFail() }
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertEqual(controller.refreshCount, 0)
    }

    func testReduceMotionRefreshesWithoutDecorationOrProgrammaticMove() {
        let controller = HandPullController()
        controller.setPreferences(enabled: true, reduceMotion: true)
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -200)
        XCTAssertFalse(controller.showsOverlay)
        controller.userScrollEnded(at: -200, framesReady: true) { _ in XCTFail() }
        XCTAssertEqual(controller.refreshCount, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isProgrammaticScroll)
    }

    func testInterruptionCancelsCompletionWithoutUpdatingMenu() {
        let controller = HandPullController()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -200)
        controller.userScrollEnded(at: -200, framesReady: true) { _ in }
        controller.apply(elapsed: 0.3)
        controller.userGestureBegan(at: 0)
        controller.apply(elapsed: 10)
        XCTAssertEqual(controller.refreshCount, 0)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isProgrammaticScroll)
        XCTAssertTrue(controller.isUserInteracting)
    }

    func testGraspIsSmoothedAndFabricMovesBeforeCatalog() {
        let controller = HandPullController()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -165)
        controller.advanceFollow(by: 1)
        XCTAssertLessThanOrEqual(controller.progress, 0.30)
        controller.geometryChanged(offset: -166)
        controller.advanceFollow(by: 1.0 / 60)
        XCTAssertGreaterThan(controller.progress, 0.30)
        XCTAssertLessThan(controller.progress, 0.46)
        controller.advanceFollow(by: 1)
        controller.userScrollEnded(at: -166, framesReady: true) { _ in }
        controller.apply(elapsed: 0.36) // p=.58: кисть уже тянет, основание ещё стоит.
        XCTAssertGreaterThan(controller.progress, 0.52)
        XCTAssertEqual(controller.surfaceHeight, 166)
        controller.apply(elapsed: 0.9)
        XCTAssertLessThan(controller.surfaceHeight, 166)
        controller.cancel()
        controller.advanceFollow(by: 1)
        XCTAssertEqual(controller.progress, 0)
    }
}

@MainActor
final class ScrollPullLimiterTests: XCTestCase {
    private final class TrackingScrollView: UIScrollView {
        var simulatedTracking = true
        override var isTracking: Bool { simulatedTracking }
    }

    func testNativeContentOffsetIsClampedOnlyDuringUserPull() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        let scroll = TrackingScrollView(frame: window.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 390, height: 1600)
        root.view.addSubview(scroll)
        let probe = ScrollPullLimiter.Probe()
        probe.maximumDistance = 96
        scroll.addSubview(probe)
        window.isHidden = false
        defer { window.isHidden = true; probe.disconnect() }
        probe.connect()
        scroll.contentOffset.y = -400
        XCTAssertEqual(scroll.contentOffset.y, -96)
        scroll.contentOffset.y = 250
        XCTAssertEqual(scroll.contentOffset.y, 250)
        scroll.simulatedTracking = false
        scroll.contentOffset.y = -120
        XCTAssertEqual(scroll.contentOffset.y, -120, "Программный возврат не ограничивается")
        scroll.simulatedTracking = true
        probe.limitEnabled = false
        scroll.contentOffset.y = -300
        XCTAssertEqual(scroll.contentOffset.y, -300)
    }
}
