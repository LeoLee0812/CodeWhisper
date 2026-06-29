//
//  SettingsView.swift
//  CodeWhisper
//
//  设置窗口：TabView 分「通用 / 模型 / 快捷键」三页，全部 Form 布局。
//  设置项双向绑定 AppSettings（@EnvironmentObject）；模型状态/进度只读 AppState.phase。
//  快捷键支持：捕获下一次按键组合写回，或从预设组合 Picker 选择。
//
//  修改记录：
//  - 朱菜：初版创建。Picker/Toggle 绑定 AppSettings；模型重新下载调 prepareModel；
//          快捷键捕获用本地 NSEvent monitor，组合写回 hotKeyCode/hotKeyModifiers。
//  - 朱菜：通用设置新增「转录模式」Picker（全量 / 流式），绑定 settings.transcriptionMode，
//          下方加说明文案。默认保持全量模式不变。
//  - 朱菜：录音 / 转录进行中禁用「转录模式」Picker（.disabled(appState.isBusy)），
//          GeneralSettingsTab 补注入 appState 以读取忙碌状态。
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .environmentObject(settings)
                .tabItem { Label("通用", systemImage: "slider.horizontal.3") }

            ModelSettingsTab()
                .environmentObject(appState)
                .environmentObject(settings)
                .tabItem { Label("模型", systemImage: "cpu") }

            HotKeySettingsTab()
                .environmentObject(settings)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - 通用设置

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    /// 辅助功能权限状态。
    @State private var hasAxPermission: Bool = ClipboardManager.hasAccessibilityPermission()

    /// 语言候选。
    private let languages: [(value: String, label: String)] = [
        ("zh", "中文"), ("en", "英文"), ("auto", "自动检测"),
    ]

    var body: some View {
        Form {
            Picker("识别语言", selection: $settings.language) {
                ForEach(languages, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }

            Picker("输出方式", selection: $settings.outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("转录模式", selection: $settings.transcriptionMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            // 录音 / 转录进行中禁用切换，避免流式停止逻辑走错（后端已有按下锁定兜底）。
            .disabled(appState.isBusy)
            // 模式说明文案。
            Text("全量模式录完整段再转、更准；流式模式边说边出字、更快")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section {
                Toggle("纠正开发者术语", isOn: $settings.fixTerms)
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                Toggle("录音完成提示音", isOn: $settings.playSound)
            }

            Section("辅助功能权限") {
                HStack {
                    Image(systemName: hasAxPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasAxPermission ? .green : .red)
                    Text(hasAxPermission ? "已授权" : "未授权（自动粘贴 / 全局热键需要）")
                        .font(.callout)
                    Spacer()
                    if !hasAxPermission {
                        Button("去授权") {
                            ClipboardManager.requestAccessibilityPermission()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAxPermission = ClipboardManager.hasAccessibilityPermission()
        }
    }
}

// MARK: - 模型设置

private struct ModelSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings

    /// 候选模型（盖鲁德可能调整默认值）。
    private let models: [(value: String, label: String)] = [
        ("openai_whisper-base", "Base（最快，精度一般）"),
        ("openai_whisper-small", "Small（均衡）"),
        ("openai_whisper-large-v3-v20240930_turbo", "Large v3 Turbo（最准，较慢）"),
    ]

    var body: some View {
        Form {
            Picker("Whisper 模型", selection: $settings.modelName) {
                ForEach(models, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }

            Section("加载状态") {
                modelStatusRow
                Button {
                    Task { await appState.prepareModel() }
                } label: {
                    Label("重新下载 / 加载模型", systemImage: "arrow.down.circle")
                }
                .disabled(isDownloading)
            }
        }
        .formStyle(.grouped)
    }

    /// 模型当前状态行。
    @ViewBuilder private var modelStatusRow: some View {
        switch appState.phase {
        case .downloadingModel(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text("正在下载 \(Int(progress * 100))%")
                ProgressView(value: progress)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        case .transcribing:
            Label("转录中…", systemImage: "waveform")
        case .recording:
            Label("录音中…", systemImage: "waveform")
        case .ready, .idle:
            Label("模型已就绪", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    /// 是否处于下载阶段。
    private var isDownloading: Bool {
        if case .downloadingModel = appState.phase { return true }
        return false
    }
}

// MARK: - 快捷键设置

private struct HotKeySettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    /// 是否正在捕获按键。
    @State private var capturing = false
    /// 本地按键监听器句柄。
    @State private var monitor: Any?

    /// 预设组合：标签 -> (keyCode, carbon modifiers)。
    private let presets: [(label: String, code: Int, mods: Int)] = [
        ("⌘M", kVK_ANSI_M, Int(cmdKey)),
        ("⌥Space", kVK_Space, Int(optionKey)),
        ("⌃Space", kVK_Space, Int(controlKey)),
        ("⌘⇧D", kVK_ANSI_D, Int(cmdKey) | Int(shiftKey)),
    ]

    var body: some View {
        Form {
            Section("录音热键") {
                HStack {
                    Text("当前：")
                    Text(settings.hotKeyDescription)
                        .font(.title3.monospaced().bold())
                    Spacer()
                    Button(capturing ? "按下组合键…" : "录制快捷键") {
                        if capturing { stopCapture() } else { startCapture() }
                    }
                    .tint(capturing ? .red : nil)
                }
                if capturing {
                    Text("请按下想要的修饰键 + 字母 / 空格组合，按 Esc 取消。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("快速预设") {
                ForEach(presets, id: \.label) { preset in
                    Button {
                        settings.hotKeyCode = preset.code
                        settings.hotKeyModifiers = preset.mods
                    } label: {
                        HStack {
                            Text(preset.label).font(.body.monospaced())
                            Spacer()
                            if settings.hotKeyCode == preset.code && settings.hotKeyModifiers == preset.mods {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopCapture() }
    }

    // MARK: 按键捕获

    /// 开始监听下一个按键组合。
    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 本地监听回调运行在主线程，断言主线程隔离以安全访问 @MainActor 状态。
            MainActor.assumeIsolated {
                handleCaptured(event)
            }
            return nil // 拦截事件，不传递给其它响应者
        }
    }

    /// 处理捕获到的按键事件（主线程隔离）。
    private func handleCaptured(_ event: NSEvent) {
        // Esc 取消捕获。
        if Int(event.keyCode) == kVK_Escape {
            stopCapture()
            return
        }
        let mods = carbonModifiers(from: event.modifierFlags)
        // 要求至少一个修饰键，避免误捕获普通输入。
        if mods != 0 {
            settings.hotKeyCode = Int(event.keyCode)
            settings.hotKeyModifiers = mods
            stopCapture()
        }
    }

    /// 停止捕获并移除监听器。
    private func stopCapture() {
        capturing = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// 把 AppKit 修饰键标志转换为 Carbon modifier flags。
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= Int(cmdKey) }
        if flags.contains(.option) { result |= Int(optionKey) }
        if flags.contains(.control) { result |= Int(controlKey) }
        if flags.contains(.shift) { result |= Int(shiftKey) }
        return result
    }
}
