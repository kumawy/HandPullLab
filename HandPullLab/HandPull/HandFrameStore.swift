import UIKit
import Observation
import ImageIO

/// Загружает только выбранный источник. Старые PNG из ZIP в приложение не входят.
@MainActor
@Observable
final class HandFrameStore {
    private(set) var descriptor: HandAnimationDescriptor
    private(set) var diagnostic: String?
    private var frameCache: [Int: UIImage] = [:]
    @ObservationIgnored private var resourceURLs: [URL] = []
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIndices: Set<Int> = []
    @ObservationIgnored private var preparationID = UUID()
    @ObservationIgnored private var requestedIndex = 0
    var cachedFrameCount: Int { frameCache.count }
    /// Память подготовленных CGImage, без накладных расходов UIImage/системного кэша.
    var decodedByteCount: Int {
        let images = Array(frameCache.values)
        return images.reduce(0) { total, image in
            guard let cg = image.cgImage else { return total }
            return total + cg.bytesPerRow * cg.height
        }
    }
    var isReady: Bool { diagnostic == nil }

    init(bundle: Bundle = .main, descriptor override: HandAnimationDescriptor? = nil) {
        do {
            if let override { descriptor = override }
            else {
                guard let url = bundle.url(forResource: "HandAnimation", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                descriptor = try JSONDecoder().decode(HandAnimationDescriptor.self, from: Data(contentsOf: url))
            }
        } catch {
            descriptor = .fallback
            diagnostic = "Не найдено корректное описание анимации HandAnimation.json. Эффект отключён."
            return
        }
        guard descriptor.canvasWidth.isFinite, descriptor.canvasHeight.isFinite,
              descriptor.canvasWidth > 0, descriptor.canvasHeight > 0,
              descriptor.topBleedFraction.isFinite else {
            diagnostic = "Некорректный размер холста анимации. Эффект отключён."
            return
        }
        if let duration = descriptor.duration {
            guard duration.isFinite, duration > 0,
                  descriptor.framesPerSecond.map({ $0.isFinite && $0 > 0 &&
                      abs($0 * duration - Double(descriptor.frameCount)) < 0.001 }) ?? true else {
                diagnostic = "Длительность и частота PNG-последовательности не согласованы. Эффект отключён."
                return
            }
        }
        guard !descriptor.frameNames.isEmpty else {
            diagnostic = "В PNG-анимации нет кадров. Эффект отключён."
            return
        }
        guard Set(descriptor.frameNames).count == descriptor.frameNames.count else {
            diagnostic = "Имена кадров повторяются. Эффект отключён."
            return
        }
        if let directory = descriptor.frameDirectory {
            guard let samples = descriptor.motionSamples, samples.count == descriptor.frameCount,
                  samples.enumerated().allSatisfy({ index, sample in
                      sample.frame == index && sample.grip.isFinite && (0...1).contains(sample.grip) &&
                      sample.opacity.isFinite && (0...1).contains(sample.opacity) &&
                      sample.pullProgress.isFinite && (0...1).contains(sample.pullProgress)
                  }), samples.first?.pullProgress == 0, samples.last?.pullProgress == 1,
                  zip(samples, samples.dropFirst()).allSatisfy({ $0.pullProgress <= $1.pullProgress }) else {
                diagnostic = "Некорректная таблица движения Remotion. Эффект отключён."
                return
            }
            for name in descriptor.frameNames {
                guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: directory),
                      let source = CGImageSourceCreateWithURL(url as CFURL,
                          [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue == descriptor.canvasWidth,
                      (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue == descriptor.canvasHeight else {
                    diagnostic = "Отсутствует или повреждён кадр \(name). Эффект отключён."
                    resourceURLs.removeAll()
                    return
                }
                resourceURLs.append(url)
            }
            // Только шесть опорных кадров. Остальные готовятся вне главного потока.
            for index in Set([0, 18, 48, 72, 108, descriptor.frameCount - 1]) where resourceURLs.indices.contains(index) {
                guard let image = Self.decode(resourceURLs[index]) else {
                    diagnostic = "Не удалось декодировать кадры Remotion. Эффект отключён."
                    frameCache.removeAll()
                    return
                }
                frameCache[index] = UIImage(cgImage: image)
            }
            return
        }
        diagnostic = "Не задан каталог PNG-последовательности. Эффект отключён."
    }

    func image(at index: Int) -> UIImage? {
        guard resourceURLs.indices.contains(index) else { return nil }
        // При быстром scrub держим ближайший готовый кадр до подготовки нового.
        return frameCache[index] ?? frameCache.min(by: { abs($0.key - index) < abs($1.key - index) })?.value
    }

    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    @discardableResult
    func prepare(around index: Int) -> Task<Void, Never>? {
        guard resourceURLs.indices.contains(index), diagnostic == nil else { return nil }
        requestedIndex = index
        let ahead = index...min(resourceURLs.count - 1, index + 6)
        if ahead.allSatisfy({ frameCache[$0] != nil }) { return preparationTask }
        if pendingIndices.contains(index) { return preparationTask }
        preparationTask?.cancel()
        let id = UUID()
        preparationID = id
        let indices = Array(index...min(resourceURLs.count - 1, index + 12)) +
            Array(max(0, index - 3)..<index).reversed()
        pendingIndices = Set(indices)
        let urls = resourceURLs
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> Void in
            var images: [Int: CGImage] = [:]
            for i in indices {
                guard !Task.isCancelled else { return }
                guard let image = Self.decode(urls[i]) else {
                    await self?.decodingFailed(id: id)
                    return
                }
                images[i] = image
            }
            guard !Task.isCancelled else { return }
            await self?.accept(images, id: id)
        }
        preparationTask = task
        return task
    }

    private func accept(_ images: [Int: CGImage], id: UUID) {
        guard preparationID == id else { return }
        var next = frameCache
        for (index, image) in images { next[index] = UIImage(cgImage: image) }
        let nearest = next.keys.filter { $0 != 0 }.sorted { abs($0 - requestedIndex) < abs($1 - requestedIndex) }
        let keep = Set([0] + Array(nearest.prefix(23)))
        frameCache = next.filter { keep.contains($0.key) }
        pendingIndices.removeAll()
        preparationTask = nil
        if frameCache[requestedIndex] == nil { prepare(around: requestedIndex) }
    }

    private func decodingFailed(id: UUID) {
        guard preparationID == id else { return }
        diagnostic = "Не удалось подготовить кадр Remotion. Эффект отключён."
        pendingIndices.removeAll()
        preparationTask = nil
    }

    func stopPreparing() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = UUID()
        pendingIndices.removeAll()
    }
}
