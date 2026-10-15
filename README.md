# sdw-hp1357-standup-macos

久坐提醒 macOS 应用：菜单栏常驻，可设置间隔提醒起身。到点时会在**所有显示器**上，从屏幕边框向中心展示一条**呼吸渐变光带**（渐变宽度 = 屏幕短边的 10%，颜色可配置），几秒后自动淡出，不打断工作流。

SwiftUI 原生实现，内存占用小，常驻后台。

## 功能

- ⏱ 可自定义提醒间隔（1–480 分钟，输入框 + 步进器）
- ⏳ 菜单栏与设置窗口显示下次提醒倒计时（菜单打开期间逐秒刷新）
- 🔄 菜单一键重置计时（提前起身就重新开始一个完整间隔）
- 🔒 屏幕锁定时停止计时，解锁后重新开始完整间隔
- 🖥 所有显示器同时展示边框呼吸渐变（含外接屏、全屏 App、不同缩放/旋转）
- 🎨 渐变颜色可配置（原生取色器）
- 🫁 呼吸动画，展示时长可自定义（1–120 秒后自动淡出）
- ⏸ 菜单栏一键暂停 / 恢复（开会、演示时）
- 🚀 开机自启（macOS 登录项）
- 🖱 覆盖层点击穿透，提醒期间不打断操作

## 系统要求

macOS 13.0（Ventura）及以上。

## 构建

```bash
# 直接运行（开发）
swift run

# 打包为 .app（ad-hoc 签名）
./Scripts/package.sh
open dist/sdw-hp1357-standup-macos.app
```

## 安装与开机自启

1. 将打包出的 `sdw-hp1357-standup-macos.app` 拷贝到 `/Applications`（自启依赖稳定路径）。
2. 首次打开若被 Gatekeeper 拦截，右键 → 打开，或 系统设置 → 隐私与安全性 → 仍要打开。
3. 点菜单栏图标 → 设置… → 打开「开机自动启动」。
4. 到 系统设置 → 通用 → 登录项 确认条目出现（首次可能需手动允许）。

## 项目结构

```
Sources/SDWStandup/
  SDWStandupApp.swift          # @main 入口
  AppDelegate.swift            # 装配、菜单栏（NSStatusItem + NSMenu）、屏幕变化监听、防 App Nap
  AppSettings.swift            # UserDefaults 唯一数据源
  Reminder/ReminderScheduler.swift   # 定时调度（休眠唤醒不漂移）
  Reminder/OverlayController.swift   # 多屏覆盖层窗口
  Reminder/BorderGlowView.swift      # 四边呼吸渐变（CALayer）
  Settings/…                   # 设置窗口
  Support/…                    # 颜色转换、倒计时格式化、自启封装
Scripts/package.sh             # swift build + 组 bundle + ad-hoc 签名
Scripts/make-icon.sh           # png -> icns
```

## 技术要点

- **工程**：SPM executable target，无 Xcode 工程，CLI 可复现构建。
- **覆盖层**：每屏一个透明 `NSWindow`（`level = .screenSaver`，`ignoresMouseEvents = true`），`collectionBehavior` 覆盖所有 Space 与全屏 App。
- **渐变**：四条 `CAGradientLayer` 各沿屏幕边向中心渐隐，宽度 = 短边 10%。
- **呼吸**：`CABasicAnimation`（opacity 0.55↔1.0 无限往返），合成器侧执行、零主线程开销。
- **定时**：`Task.sleep(for:)`（`ContinuousClock`）+ 绝对时间锚定，休眠唤醒后立即补触发。

## 免责声明

未公证的个人自用应用。给他人分发时若需免拦截体验，需 Apple Developer 账号签名 + 公证。
