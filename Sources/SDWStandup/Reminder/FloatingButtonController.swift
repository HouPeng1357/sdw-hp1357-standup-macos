import AppKit

/// 右下角悬浮确认按钮：提醒期间显示，点击即确认提醒（相当于点击菜单栏图标）。
///
/// 提醒期间菜单栏图标会被绿色进度覆盖、肉眼难找，这里在屏幕右下角放一个
/// 白框白字的悬浮按钮作为确认入口，随提醒状态一起显示 / 隐藏。
final class FloatingButtonController {
    static let shared = FloatingButtonController()

    private var window: NSWindow?

    private init() {}

    func show() {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        if window == nil { build() }
        guard let window, let button = window.contentView as? FloatingConfirmButton else { return }

        // 每次显示都按当前主屏几何重新定位，屏幕变化后也不会跑偏。
        let size = button.intrinsicSize
        let margin: CGFloat = 20
        let visible = screen.visibleFrame
        window.setFrame(NSRect(x: visible.maxX - size.width - margin,
                               y: visible.minY + margin,
                               width: size.width,
                               height: size.height),
                        display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func build() {
        let button = FloatingConfirmButton(title: "知道了") {
            ReminderScheduler.shared.acknowledgeReminder()
        }

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentView = button
        self.window = window
    }
}

/// 白框白字的悬浮按钮视图。
private final class FloatingConfirmButton: NSView {
    private let title: String
    private let action: () -> Void

    private let font = NSFont.systemFont(ofSize: 14, weight: .medium)
    private let borderWidth: CGFloat = 1.5
    private let cornerRadius: CGFloat = 9
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 10

    var intrinsicSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(text.width) + horizontalPadding * 2,
                      height: ceil(text.height) + verticalPadding * 2)
    }

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        NSColor.white.setStroke()
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let text = (title as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - text.width) / 2,
                             y: (bounds.height - text.height) / 2)
        (title as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}
