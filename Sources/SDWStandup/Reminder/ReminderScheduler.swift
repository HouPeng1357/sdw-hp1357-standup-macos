import AppKit

/// 提醒调度循环：按绝对时间锚定下一次触发，休眠唤醒后不漂移。
final class ReminderScheduler: ObservableObject {
    static let shared = ReminderScheduler()

    private let settings = AppSettings.shared
    private var timer: DispatchSourceTimer?

    /// 下次提醒的触发时间（nil = 已暂停 / 未启动），供 UI 显示倒计时。
    @Published private(set) var nextFireDate: Date?

    /// 提醒已触发但用户尚未确认。期间菜单栏图标保持绿色，
    /// 直到用户点击菜单栏图标确认后重新计时。
    @Published private(set) var hasPendingReminder = false

    private init() {}

    func start() {
        timer?.cancel()
        timer = nil

        let interval = Double(settings.intervalMinutes) * 60
        let next = Date().addingTimeInterval(interval)
        nextFireDate = next

        let t = DispatchSource.makeTimerSource(queue: .main)
        // 用 wallDeadline（墙上时钟）：系统睡眠 / App Nap 挂起期间也照常计时，
        // 唤醒后若已过期会立即补触发，避免长 sleep 被冻结后永不醒来。
        t.schedule(wallDeadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            self?.hasPendingReminder = true
            OverlayController.shared.show()
            self?.nextFireDate = Date().addingTimeInterval(interval)
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        nextFireDate = nil
    }

    /// 用户确认提醒：清除绿色状态并重新开始完整间隔。
    func acknowledgeReminder() {
        hasPendingReminder = false
        start()
    }
}
