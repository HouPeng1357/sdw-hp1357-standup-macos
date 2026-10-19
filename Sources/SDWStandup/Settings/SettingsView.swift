import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var scheduler = ReminderScheduler.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 下次提醒倒计时
            HStack {
                rowLabel("下次提醒")
                Spacer()
                if settings.isPaused {
                    Text("提醒已暂停").foregroundStyle(.secondary)
                } else if let next = scheduler.nextFireDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(CountdownFormatter.text(to: next))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            // 提醒间隔
            HStack {
                rowLabel("提醒间隔")
                Spacer()
                numberField(value: $settings.intervalMinutes, unit: "分钟")
            }
            .onChange(of: settings.intervalMinutes) { v in
                clamp(&settings.intervalMinutes, v, 1...480)
            }

            // 一直展示提示
            HStack {
                rowLabel("一直展示提示")
                Spacer()
                Toggle("", isOn: $settings.alwaysShowReminder)
                    .labelsHidden()
            }

            // 展示时长（勾选「一直展示提示」后隐藏）
            if !settings.alwaysShowReminder {
                HStack {
                    rowLabel("展示时长")
                    Spacer()
                    numberField(value: $settings.displaySeconds, unit: "秒")
                }
                .onChange(of: settings.displaySeconds) { v in
                    clamp(&settings.displaySeconds, v, 1...120)
                }
            }

            // 渐变颜色
            HStack {
                rowLabel("渐变颜色")
                Spacer()
                NSColorWellRepresentable(color: accentBinding)
            }

            // 开机自启
            HStack {
                rowLabel("开机自动启动")
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            if let launchError {
                Text(launchError)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - 私有

    /// 标签固定自然宽度，避免被截断成「提醒间…」
    private func rowLabel(_ text: String) -> some View {
        Text(text).fixedSize()
    }

    private func numberField(value: Binding<Int>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary).fixedSize()
            Stepper("", value: value).labelsHidden()
        }
    }

    private func clamp(_ value: inout Int, _ newValue: Int, _ range: ClosedRange<Int>) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        if clamped != newValue { value = clamped }
    }

    private var accentBinding: Binding<NSColor> {
        Binding(
            get: { settings.accentColor },
            set: { settings.accentColorHex = ColorHex.string(from: $0) }
        )
    }
}

/// 用原生 NSColorWell 取色，直接得到 NSColor（避开 Color→NSColor 转换的坑）。
private struct NSColorWellRepresentable: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: NSColorWellRepresentable
        init(_ parent: NSColorWellRepresentable) { self.parent = parent }
        @objc func changed(_ well: NSColorWell) {
            parent.color = well.color
        }
    }
}
