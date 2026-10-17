import SwiftUI

/// Альфа-маска ткани: свободная поверхность остаётся видимой,
/// иконки и подписи получают чистое окружение.
struct ClothProtectionMask: View {
    let protectedAreas: [CGRect]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut
            context.drawLayer { halo in
                halo.addFilter(.blur(radius: 12))
                for area in protectedAreas {
                    halo.fill(Path(roundedRect: area.insetBy(dx: -24, dy: -24), cornerRadius: 24),
                              with: .color(.black))
                }
            }
            // Центральная область полностью чистая; размыт только внешний край.
            for area in protectedAreas {
                context.fill(Path(roundedRect: area.insetBy(dx: -2, dy: -2), cornerRadius: 6),
                             with: .color(.black))
            }
        }
    }
}
