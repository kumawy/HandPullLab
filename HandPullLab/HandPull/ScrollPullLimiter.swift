import SwiftUI
import UIKit

/// Ограничивает только отрицательный overscroll существующего SwiftUI ScrollView.
/// Его delegate и обычная прокрутка остаются под управлением SwiftUI.
struct ScrollPullLimiter: UIViewRepresentable {
    let maximumDistance: Double
    let enabled: Bool

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.maximumDistance = maximumDistance
        view.limitEnabled = enabled
        view.connect()
    }

    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.disconnect() }

    final class Probe: UIView {
        var maximumDistance = 96.0
        var limitEnabled = true
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var isClamping = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { disconnect() }
            else { connect() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            connect()
        }

        func connect() {
            guard scrollView == nil, window != nil else { return }
            var ancestor = superview
            while let candidate = ancestor {
                if let scroll = candidate as? UIScrollView {
                    scrollView = scroll
                    observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.clamp() }
                    }
                    return
                }
                ancestor = candidate.superview
            }
        }

        private func clamp() {
            guard limitEnabled, !isClamping, let scrollView,
                  scrollView.isTracking || scrollView.isDragging else { return }
            let limit = -scrollView.adjustedContentInset.top - max(1, maximumDistance)
            guard scrollView.contentOffset.y < limit else { return }
            isClamping = true
            // Синхронно, до отрисовки: контент физически не проходит ниже ткани.
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: limit)
            isClamping = false
        }

        func disconnect() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }
    }
}
