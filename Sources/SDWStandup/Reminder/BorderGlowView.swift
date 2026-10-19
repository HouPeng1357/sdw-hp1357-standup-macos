import AppKit
import QuartzCore

/// 屏幕边框呼吸渐变覆盖层。
///
/// 三层结构，动画互不冲突：
///   fadeLayer     (外层) 整体透明度，负责淡入 / 淡出
///    └─ breatheLayer (中层) 整体透明度，负责 0.55↔1.0 无限呼吸
///         ├─ 上 / 下 / 左 / 右 四条 CAGradientLayer（各从边框向中心渐隐）
final class BorderGlowView: NSView {
    private let fadeLayer = CALayer()
    private let breatheLayer = CALayer()
    private var edgeLayers: [CAGradientLayer] = []

    private let color: NSColor
    private let bandWidth: CGFloat

    init(frame: NSRect, color: NSColor, bandWidth: CGFloat) {
        self.color = color
        self.bandWidth = bandWidth
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor

        fadeLayer.frame = bounds
        breatheLayer.frame = bounds
        layer.addSublayer(fadeLayer)
        fadeLayer.addSublayer(breatheLayer)

        let w = bounds.width
        let h = bounds.height
        let band = max(1, min(bandWidth, min(w, h) / 2))
        let cg = color.cgColor
        let clear = NSColor.clear.cgColor

        // 每条边：一个线性渐变层，颜色从屏幕边框（外侧）向中心（内侧）渐隐。
        let top = makeEdge(CGRect(x: 0, y: h - band, width: w, height: band),
                           start: CGPoint(x: 0.5, y: 1), end: CGPoint(x: 0.5, y: 0),
                           color: cg, clear: clear)
        let bottom = makeEdge(CGRect(x: 0, y: 0, width: w, height: band),
                              start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1),
                              color: cg, clear: clear)
        let left = makeEdge(CGRect(x: 0, y: 0, width: band, height: h),
                            start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                            color: cg, clear: clear)
        let right = makeEdge(CGRect(x: w - band, y: 0, width: band, height: h),
                             start: CGPoint(x: 1, y: 0.5), end: CGPoint(x: 0, y: 0.5),
                             color: cg, clear: clear)
        edgeLayers = [top, bottom, left, right]
        for e in edgeLayers { breatheLayer.addSublayer(e) }
    }

    private func makeEdge(_ frame: CGRect, start: CGPoint, end: CGPoint,
                          color: CGColor, clear: CGColor) -> CAGradientLayer {
        let l = CAGradientLayer()
        l.frame = frame
        l.colors = [color, clear]
        l.startPoint = start
        l.endPoint = end
        return l
    }

    /// 淡入后进入无限呼吸。
    func fadeInThenBreathe(breathCycle: Double) {
        breatheLayer.removeAnimation(forKey: "breathe")
        breatheLayer.opacity = 1
        fadeLayer.removeAllAnimations()
        fadeLayer.opacity = 1 // 模型值设为最终值，动画只驱动展示层

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.startBreathing(cycle: breathCycle)
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.25
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fadeLayer.add(a, forKey: "fadeIn")
        CATransaction.commit()
    }

    func startBreathing(cycle: Double) {
        breatheLayer.removeAnimation(forKey: "breathe")
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue = 0.55
        a.duration = cycle
        a.autoreverses = true
        // 只呼吸 3 次后停在满亮度，避免无限动画持续占用 GPU。
        a.repeatCount = 3
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breatheLayer.add(a, forKey: "breathe")
    }

    /// 淡出，完成后回调（用于 orderOut）。
    func fadeOut(duration: Double, completion: @escaping () -> Void) {
        breatheLayer.removeAnimation(forKey: "breathe")
        fadeLayer.removeAnimation(forKey: "fadeIn")
        let current = fadeLayer.presentation()?.opacity ?? 1
        fadeLayer.opacity = 0

        CATransaction.begin()
        CATransaction.setCompletionBlock { completion() }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = current
        a.toValue = 0
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fadeLayer.add(a, forKey: "fadeOut")
        CATransaction.commit()
    }
}
