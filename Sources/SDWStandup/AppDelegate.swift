import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var activity: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    private var statusItem: NSStatusItem?
    private var countdownItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var resetItem: NSMenuItem?
    private var menuTimer: Timer?
    private var pendingReminder = false
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 开发期 swift run 裸跑也不显示 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 防 App Nap 节流定时器
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated,
                                                         reason: "Reminder scheduling")

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // 屏幕锁定时停止计时，解锁后重新开始完整间隔
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self, selector: #selector(screenLocked(_:)),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(
            self, selector: #selector(screenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        setupMenuBar()

        let settings = AppSettings.shared

        settings.$isPaused
            .dropFirst()
            .sink { [weak self] paused in
                self?.refreshPauseUI()
                paused ? ReminderScheduler.shared.stop() : ReminderScheduler.shared.start()
            }
            .store(in: &cancellables)

        settings.$intervalMinutes
            .dropFirst()
            .sink { _ in
                if !settings.isPaused { ReminderScheduler.shared.start() }
            }
            .store(in: &cancellables)

        ReminderScheduler.shared.$hasPendingReminder
            .dropFirst()
            .sink { [weak self] pending in
                self?.pendingReminder = pending
                self?.refreshStatusIcon()
            }
            .store(in: &cancellables)

        // 菜单栏进度图标逐秒重绘（开销极小）
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)

        // 全局监听 ESC：提醒待确认时按 ESC 相当于点击菜单栏图标（需辅助功能权限）。
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async {
                self?.handleEscapeKey()
            }
        }

        if !settings.isPaused {
            ReminderScheduler.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    @objc private func screensChanged(_ note: Notification) {
        OverlayController.shared.screensDidChange()
    }

    // MARK: - 屏幕锁定 / 解锁

    @objc private func screenLocked(_ note: Notification) {
        ReminderScheduler.shared.stop()
    }

    @objc private func screenUnlocked(_ note: Notification) {
        guard !AppSettings.shared.isPaused else { return }
        ReminderScheduler.shared.start()
    }

    // MARK: - 菜单栏（NSStatusItem）

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let countdown = NSMenuItem(title: " ", action: nil, keyEquivalent: "")
        countdown.isEnabled = false
        menu.addItem(countdown)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "暂停提醒", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let preview = NSMenuItem(title: "立即提醒（预览）", action: #selector(previewReminder(_:)), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)

        let reset = NSMenuItem(title: "重置计时", action: #selector(resetTimer(_:)), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        countdownItem = countdown
        pauseItem = pause
        resetItem = reset
        updateCountdown()
        refreshStatusIcon()
    }

    // MARK: - NSMenuDelegate：菜单打开期间逐秒刷新倒计时

    func menuWillOpen(_ menu: NSMenu) {
        // 点击菜单栏图标即视为确认提醒：清除绿色并重新计时。
        if pendingReminder {
            ReminderScheduler.shared.acknowledgeReminder()
        }
        refreshPauseUI()
        resetItem?.isEnabled = !AppSettings.shared.isPaused
        updateCountdown()
        // 菜单跟踪运行在 event tracking mode，需注册 .common 才能在打开期间触发
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    // MARK: - 私有

    private func updateCountdown() {
        guard let countdownItem else { return }
        if AppSettings.shared.isPaused {
            countdownItem.title = "提醒已暂停"
        } else if let next = ReminderScheduler.shared.nextFireDate {
            countdownItem.title = "下次提醒：" + CountdownFormatter.text(to: next)
        } else {
            countdownItem.title = "计时已停止"
        }
    }

    private func refreshPauseUI() {
        let paused = AppSettings.shared.isPaused
        pauseItem?.title = paused ? "恢复提醒" : "暂停提醒"
        refreshStatusIcon()
    }

    /// 统一刷新菜单栏图标：
    /// 未确认提醒 → 全绿；暂停 → pause.circle；正常 → 按倒计时进度从下往上变绿。
    private func refreshStatusIcon() {
        if pendingReminder {
            statusItem?.button?.image = progressStandIcon(progress: 1)
            return
        }
        if AppSettings.shared.isPaused {
            let image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "久坐提醒")
            image?.isTemplate = true
            statusItem?.button?.image = image
            return
        }
        let progress = ReminderScheduler.shared.progress ?? 0
        // 超过 80% 但未到点时封顶在 80%，避免肉眼误判为已到点全绿。
        statusItem?.button?.image = progressStandIcon(progress: min(progress, 0.8))
    }

    /// 站立图标：底部 progress 比例绿色，顶部为菜单栏默认色（labelColor 自动适配明暗）。
    /// 用符号自身尺寸作画布，保证进度各阶段与全绿图标大小一致。
    private func progressStandIcon(progress: Double) -> NSImage? {
        guard let bg = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor])),
              let fg = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemGreen]))
        else { return nil }

        let size = bg.size
        let fillHeight = max(0, min(size.height * CGFloat(progress), size.height))
        return NSImage(size: size, flipped: false) { rect in
            bg.draw(in: rect)
            if fillHeight > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: size.width, height: fillHeight)).addClip()
                fg.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    /// ESC 确认提醒（相当于点击菜单栏图标）。
    private func handleEscapeKey() {
        guard pendingReminder else { return }
        ReminderScheduler.shared.acknowledgeReminder()
    }

    // MARK: - 菜单动作

    @objc private func togglePause(_ sender: Any?) {
        AppSettings.shared.isPaused.toggle()
    }

    @objc private func previewReminder(_ sender: Any?) {
        OverlayController.shared.show()
    }

    @objc private func resetTimer(_ sender: Any?) {
        guard !AppSettings.shared.isPaused else { return }
        ReminderScheduler.shared.start()
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
