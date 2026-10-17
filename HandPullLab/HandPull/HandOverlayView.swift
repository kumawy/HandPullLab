import SwiftUI

/// Единственный визуальный источник — текущая последовательность руки и ткани.
struct HandOverlayView: View {
    let controller: HandPullController
    let frames: HandFrameStore
    let size: CGSize
    let safeAreaTop: CGFloat
    let protectedAreas: [CGRect]
    let headerBottom: CGFloat?

    var body: some View {
        if controller.showsOverlay {
            let descriptor = frames.descriptor
            let width = size.width
            let height = width * descriptor.canvasHeight / descriptor.canvasWidth
            let pullHeight = (descriptor.upwardPullPixels ?? 72) * width / descriptor.canvasWidth
            // Оставляем под пальцами место для веера складок. Раньше линия
            // хвата почти совпадала с нижней маской и ткань целиком срезалась.
            let y = -safeAreaTop - width * (descriptor.topBleedFraction + 0.14) +
                controller.renderedSceneAdjustment(renderedPullHeight: pullHeight)
            // Ткань проходит через свободные участки прозрачного header,
            // а ниже него заканчивается перед заголовком каталога.
            let bottom = max(controller.neutralHeight, headerBottom ?? 0)
            let clipHeight = controller.isPreviewing ? height : min(height, max(0, bottom - y))
            let fade = min(14.0, clipHeight)
            Group {
                if let image = frames.image(at: controller.frameIndex) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(descriptor.canvasWidth / descriptor.canvasHeight, contentMode: .fit)
                }
            }
            .frame(width: width, height: height)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.white.frame(height: max(0, clipHeight - fade))
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                }
            }
            .mask {
                ClothProtectionMask(protectedAreas:
                    (protectedAreas + systemIconAreas).map { $0.offsetBy(dx: 0, dy: -y) })
            }
            .offset(y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: controller.frameIndex, initial: true) { _, index in frames.prepare(around: index) }
            .onDisappear { frames.stopPreparing() }
        }
    }

    private var systemIconAreas: [CGRect] {
        guard safeAreaTop > 0 else { return [] }
        // UIKit не публикует фреймы отдельных системных значков. Защищаем
        // их боковые зоны внутри реальной верхней safe area с запасом.
        let height = min(44, safeAreaTop)
        let y = -safeAreaTop + (safeAreaTop - height) / 2
        return [
            CGRect(x: 16, y: y, width: size.width * 0.20, height: height),
            CGRect(x: size.width * 0.76, y: y, width: size.width * 0.24 - 16, height: height)
        ]
    }
}
