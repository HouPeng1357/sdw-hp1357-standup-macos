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

    /// 统一刷新菜单栏图标：有未确认的提醒时显示绿色，否则按暂停 / 运行状态显示。
    private func refreshStatusIcon() {
        let paused = AppSettings.shared.isPaused
        let symbolName = pendingReminder ? "figure.stand" : (paused ? "pause.circle" : "figure.stand")
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "久坐提醒")

        if pendingReminder {
            // palette 着色生成真正的绿色图像；必须关闭 isTemplate，否则系统会忽略颜色按模板色渲染。
            let colored = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemGreen]))
            colored?.isTemplate = false
            statusItem?.button?.image = colored
        } else {
            image?.isTemplate = true
            statusItem?.button?.image = image
        }
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
