import AppKit
import SwiftUI

/// 应用设置的唯一数据源：所有状态持久化到 UserDefaults，
/// 菜单栏、设置窗口、调度器、覆盖层都订阅同一个实例。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var intervalMinutes: Int {
        didSet { defaults.set(intervalMinutes, forKey: Keys.intervalMinutes) }
    }
    @Published var displaySeconds: Int {
        didSet { defaults.set(displaySeconds, forKey: Keys.displaySeconds) }
    }
    @Published var alwaysShowReminder: Bool {
        didSet { defaults.set(alwaysShowReminder, forKey: Keys.alwaysShowReminder) }
    }
    @Published var accentColorHex: String {
        didSet { defaults.set(accentColorHex, forKey: Keys.accentColorHex) }
    }
    @Published var breathCycleSeconds: Double {
        didSet { defaults.set(breathCycleSeconds, forKey: Keys.breathCycleSeconds) }
    }
    @Published var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    var accentColor: NSColor { ColorHex.parse(accentColorHex) }

    private init() {
        defaults.register(defaults: [
            Keys.intervalMinutes: 45,
            Keys.displaySeconds: 12,
            Keys.alwaysShowReminder: false,
            Keys.accentColorHex: "#4C8DFF",
            Keys.breathCycleSeconds: 1.2,
            Keys.isPaused: false,
        ])
        intervalMinutes = defaults.integer(forKey: Keys.intervalMinutes)
        displaySeconds = defaults.integer(forKey: Keys.displaySeconds)
        alwaysShowReminder = defaults.bool(forKey: Keys.alwaysShowReminder)
        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? "#4C8DFF"
        breathCycleSeconds = defaults.double(forKey: Keys.breathCycleSeconds)
        isPaused = defaults.bool(forKey: Keys.isPaused)
    }

    private enum Keys {
        static let intervalMinutes = "intervalMinutes"
        static let displaySeconds = "displaySeconds"
        static let alwaysShowReminder = "alwaysShowReminder"
        static let accentColorHex = "accentColorHex"
        static let breathCycleSeconds = "breathCycleSeconds"
        static let isPaused = "isPaused"
    }
}
