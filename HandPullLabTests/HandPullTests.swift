import XCTest
import UIKit
import SwiftUI
@testable import HandPullLab

@MainActor
final class ClothProtectionMaskTests: XCTestCase {
    func testMaskPreservesFabricBetweenControlsAndClearsTheIcons() throws {
        let renderer = ImageRenderer(content:
            ClothProtectionMask(protectedAreas: [CGRect(x: 20, y: 20, width: 44, height: 44)])
                .frame(width: 120, height: 90))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: 120 * 90 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 120, height: 90,
            bitsPerComponent: 8, bytesPerRow: 120 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 90)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 120, height: 90))
        XCTAssertEqual(pixels[(42 * 120 + 42) * 4 + 3], 0, "Под иконкой ткани нет")
        XCTAssertEqual(pixels[(42 * 120 + 24) * 4 + 3], 0, "Защищены и края иконки")
        XCTAssertGreaterThanOrEqual(pixels[(42 * 120 + 110) * 4 + 3], 240, "Между элементами ткань видна")
        let transition = pixels[(42 * 120 + 77) * 4 + 3]
        XCTAssertGreaterThan(transition, 0, "Переход мягкий")
        XCTAssertLessThan(transition, 255, "Нет резкой прямоугольной границы")
    }
}

final class HandPullTimelineTests: XCTestCase {
    func testFrameBoundariesAndInvalidInputs() {
        XCTAssertNil(HandPullTimeline.frameIndex(progress: 0.5, count: 0))
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: -1, count: 45), 0)
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: 0, count: 45), 0)
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: 1, count: 45), 44)
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: .infinity, count: 45), 44)
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: .nan, count: 45), 0)
        for value in stride(from: -2.0, through: 2, by: 0.001) {
            XCTAssertTrue((0..<45).contains(HandPullTimeline.frameIndex(progress: value, count: 45)!))
        }
        XCTAssertEqual(HandPullTimeline.progress(elapsed: 4, duration: 0), 1)
        XCTAssertEqual(HandPullTimeline.progress(elapsed: -1, duration: 3), 0)
        XCTAssertEqual(HandPullTimeline.progress(elapsed: 1.5, duration: 3), 0.5)
        XCTAssertEqual(HandPullTimeline.progress(elapsed: 9, duration: 3), 1)
    }

    func testChoreography() {
        XCTAssertEqual(HandPullTimeline.phase(progress: 0), .appearing)
        XCTAssertEqual(HandPullTimeline.phase(progress: 20.0/45), .gripping)
        XCTAssertEqual(HandPullTimeline.phase(progress: 30.0/45), .returning)
        XCTAssertEqual(HandPullTimeline.phase(progress: 0.96), .disappearing)
        XCTAssertEqual(HandPullTimeline.catalogReturnFraction(0.6), 0, "Сначала тянется ткань")
        XCTAssertGreaterThan(HandPullTimeline.catalogReturnFraction(0.75), 0)
        XCTAssertEqual(HandPullTimeline.surfaceFraction(0), 0)
        XCTAssertEqual(HandPullTimeline.surfaceFraction(1), 0)
    }
}

@MainActor
final class HandPullControllerTests: XCTestCase {
    func testReturnUsesSameTimelineAndCancelIsIdempotent() {
        let controller = HandPullController()
        var offsets: [Double] = []
        controller.geometryChanged(offset: 100)
        controller.replay(framesReady: true) { offsets.append($0) }
        controller.apply(elapsed: 1)
        XCTAssertTrue(offsets.isEmpty)
        controller.apply(elapsed: 2)
        XCTAssertEqual(controller.phase, .returning)
        XCTAssertTrue(controller.isProgrammaticScroll)
        XCTAssertTrue((0..<100).contains(offsets.last!))
        controller.cancel()
        controller.cancel()
        XCTAssertFalse(controller.showsOverlay)
        XCTAssertFalse(controller.isProgrammaticScroll)
        let count = offsets.count
        controller.apply(elapsed: 3)
        XCTAssertEqual(offsets.count, count)
    }

    func testRepeatedReplayCompletionAndInterruption() {
        let controller = HandPullController()
        var calls = 0
        controller.replay(framesReady: true) { _ in calls += 1 }
        controller.replay(framesReady: true) { _ in XCTFail("Parallel playback") }
        controller.apply(elapsed: 3)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isProgrammaticScroll)
        controller.replay(framesReady: true) { _ in calls += 1 }
        controller.userGestureBegan(at: 42)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.isUserInteracting)
        controller.apply(elapsed: 3)
        XCTAssertEqual(calls, 1)
    }

    func testPreferencesAndPreview() {
        let controller = HandPullController()
        controller.setPreferences(enabled: true, reduceMotion: true)
        controller.replay(framesReady: true) { _ in XCTFail() }
        controller.preview(progress: 0.5, framesReady: true)
        XCTAssertFalse(controller.showsOverlay)
        controller.setPreferences(enabled: true, reduceMotion: false)
        controller.replay(framesReady: false) { _ in XCTFail() }
        XCTAssertFalse(controller.isPlaying)
        controller.replay(framesReady: true) { _ in }
        controller.preview(progress: 0.5, framesReady: true)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.isPreviewing)
        XCTAssertEqual(controller.frameIndex, 22)
        controller.reset()
        XCTAssertFalse(controller.showsOverlay)
    }
}

@MainActor
final class HandFrameStoreTests: XCTestCase {
    func testRemotionSequenceHasTheExportedTimingAndCanvas() {
        let store = HandFrameStore()
        XCTAssertTrue(store.isReady)
        XCTAssertEqual(store.descriptor.frameCount, 144)
        XCTAssertEqual(store.descriptor.duration, 2.4)
        XCTAssertEqual(store.descriptor.framesPerSecond, 60)
        XCTAssertEqual(store.descriptor.canvasWidth, 512)
        XCTAssertEqual(store.descriptor.canvasHeight, 512)
    }

    func testSequenceKeepsFullResolutionWithABoundedCache() async {
        let store = HandFrameStore()
        XCTAssertNil(store.diagnostic)
        XCTAssertTrue(store.isReady)
        XCTAssertEqual(store.descriptor.renderer, .pngSequence)
        XCTAssertEqual(store.descriptor.frameCount, 144)
        XCTAssertEqual(store.descriptor.duration, 2.4)
        XCTAssertEqual(store.descriptor.framesPerSecond, 60)
        XCTAssertEqual(store.descriptor.frameDirectory, "HandPullRemotion")
        XCTAssertNil(store.image(at: -1))
        XCTAssertNil(store.image(at: 144))
        for index in [0, 24, 48, 72, 108, 50, 143] {
            await store.prepare(around: index)?.value
            XCTAssertEqual(store.image(at: index)?.cgImage?.width, 512)
            XCTAssertEqual(store.image(at: index)?.cgImage?.height, 512)
            XCTAssertLessThanOrEqual(store.cachedFrameCount, 24)
            XCTAssertLessThanOrEqual(store.decodedByteCount, 24 * 512 * 512 * 4)
        }
        for index in [0, 143] {
            await store.prepare(around: index)?.value
            var bytes = [UInt8](repeating: 255, count: 512 * 512 * 4)
            let context = CGContext(data: &bytes, width: 512, height: 512,
                                   bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.clear(CGRect(x: 0, y: 0, width: 512, height: 512))
            context.draw(store.image(at: index)!.cgImage!, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 0 })
        }
        store.stopPreparing()
    }

    func testRemotionTimingMatchesTheController() {
        let store = HandFrameStore()
        var configuration = HandPullConfiguration()
        configuration.use(store.descriptor)
        XCTAssertEqual(configuration.surfaceFraction(18.0 / 144), 1,
                       "Make room for the full hand before it descends")
        XCTAssertEqual(configuration.catalogReturnFraction(75.0 / 144), 0)
        XCTAssertGreaterThan(configuration.catalogReturnFraction(90.0 / 144), 0.5)
        XCTAssertEqual(configuration.catalogReturnFraction(108.0 / 144), 1)
        XCTAssertEqual(configuration.gestureReadyProgress, 0.5)
        for frame in 75...112 {
            XCTAssertEqual(store.descriptor.motionSamples?[frame].grip, 1)
        }
        XCTAssertEqual(HandPullTimeline.frameIndex(progress: 1, count: store.descriptor.frameCount), 143)
        var invalid = store.descriptor
        invalid.framesPerSecond = 30
        XCTAssertFalse(HandFrameStore(descriptor: invalid).isReady)
        invalid = store.descriptor
        invalid.motionSamples = []
        XCTAssertFalse(HandFrameStore(descriptor: invalid).isReady)
    }

    func testScrollAndSurfaceFinishReturningBeforeGripReleases() {
        let store = HandFrameStore()
        var configuration = HandPullConfiguration()
        configuration.use(store.descriptor)
        let controller = HandPullController(configuration: configuration)
        var offsets: [Double] = []
        controller.geometryChanged(offset: 120)
        controller.replay(framesReady: store.isReady) { offsets.append($0) }
        controller.apply(elapsed: 75.0 / 60)
        XCTAssertTrue(offsets.isEmpty, "Do not move the list before the hand pulls")
        controller.apply(elapsed: 90.0 / 60)
        XCTAssertGreaterThan(controller.surfaceHeight, 0)
        XCTAssertLessThan(offsets.last!, 120)
        XCTAssertGreaterThan(offsets.last!, 0)
        controller.apply(elapsed: 108.0 / 60)
        XCTAssertEqual(offsets.last!, 0)
        XCTAssertEqual(controller.surfaceHeight, 0)
        XCTAssertEqual(configuration.motionSamples[controller.frameIndex].grip, 1)
        controller.cancel()
        controller.userGestureBegan(at: 0)
        controller.geometryChanged(offset: -166)
        controller.advanceFollow(by: 1)
        XCTAssertEqual(controller.progress, 0.5)
        controller.userScrollEnded(at: -166, framesReady: true) { _ in }
        XCTAssertEqual(controller.surfaceHeight, 166)
        controller.apply(elapsed: (108.0 - 72) / 60)
        XCTAssertEqual(controller.surfaceHeight, 0)
        XCTAssertEqual(configuration.motionSamples[controller.frameIndex].grip, 1)
        controller.cancel()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isProgrammaticScroll)
        XCTAssertFalse(controller.showsOverlay)
    }

    func testMissingSequenceDisablesEffectWithDiagnostic() {
        var descriptor = HandAnimationDescriptor.fallback
        descriptor.renderer = .pngSequence
        descriptor.frameNames = ["missing_new_frame"]
        let store = HandFrameStore(descriptor: descriptor)
        XCTAssertFalse(store.isReady)
        XCTAssertNotNil(store.diagnostic)
        XCTAssertNil(store.image(at: 0))
        descriptor.frameNames = ["duplicate", "duplicate"]
        XCTAssertFalse(HandFrameStore(descriptor: descriptor).isReady)
        descriptor.frameNames = []
        XCTAssertFalse(HandFrameStore(descriptor: descriptor).isReady)
    }
}
