import AppKit

/// 管理所有显示器上的全屏覆盖层窗口：创建、显隐、屏幕变化重建。
final class OverlayController {
    static let shared = OverlayController()

    private let settings = AppSettings.shared
    private var windows: [NSWindow] = []
    private var dismissTask: Task<Void, Never>?
    private var builtSignature = ""
    private var isShowing = false

    private init() {}

    var visible: Bool { isShowing }

    func show(persistent: Bool = false) {
        rebuildIfNeeded()
        for w in windows {
            w.orderFrontRegardless()
            (w.contentView as? BorderGlowView)?
                .fadeInThenBreathe(breathCycle: settings.breathCycleSeconds)
        }
        isShowing = true
        if persistent {
            // 一直展示：不排定自动淡出，等用户确认后由 hide() 关闭。
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isShowing else { return }
        isShowing = false
        for w in windows {
            if let view = w.contentView as? BorderGlowView {
                view.fadeOut(duration: 0.8) { [weak w] in w?.orderOut(nil) }
            } else {
                w.orderOut(nil)
            }
        }
    }

    func screensDidChange() {
        if isShowing {
            hide()
            show()
        } else {
            builtSignature = ""
        }
    }

    // MARK: - 私有

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let seconds = Double(settings.displaySeconds)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.hide()
        }
    }

    private func rebuildIfNeeded() {
        let sig = signature()
        guard sig != builtSignature || windows.isEmpty else { return }
        for w in windows {
            w.orderOut(nil)
            w.contentView = nil
        }
        windows = NSScreen.screens.map { makeWindow(for: $0) }
        builtSignature = sig
    }

    private func signature() -> String {
        let frames = NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: "|")
        return frames + "|" + settings.accentColorHex
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let frame = screen.frame
        let band = 0.10 * min(frame.width, frame.height)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = BorderGlowView(frame: NSRect(origin: .zero, size: frame.size),
                                            color: settings.accentColor,
                                            bandWidth: band)
        return window
    }
}
