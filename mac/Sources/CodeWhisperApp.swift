//
//  CodeWhisperApp.swift
//  CodeWhisper
//
//  应用入口：@main App + MenuBarExtra（窗口风格）。
//  在入口处用 @StateObject 持有 AppState 并注入 environment，
//  菜单栏图标随 AppState.phase 动态变化，首启 task 中调用 prepareModel()。
//
//  修改记录：
//  - 朱菜：初版创建。MenuBarExtra(.window) + Settings 场景；图标按 phase 切换。
//

import SwiftUI

@main
struct CodeWhisperApp: App {
    /// 全局唯一协调器，入口持有，子视图通过 environmentObject 读取。
    @StateObject private var appState = AppState()

    var body: some Scene {
        // 菜单栏常驻入口，窗口风格弹出 MenuContentView。
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(appState.history)
        } label: {
            // 图标随录音/转录/下载/错误等阶段变化。
            Image(systemName: menuBarSymbol(for: appState.phase))
        }
        .menuBarExtraStyle(.window)

        // 标准设置窗口（⌘,）。
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
        }
    }

    /// 根据当前阶段选择菜单栏 SF Symbol。
    private func menuBarSymbol(for phase: AppState.Phase) -> String {
        switch phase {
        case .idle, .ready:
            return "mic"
        case .recording:
            return "waveform"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .downloadingModel:
            return "arrow.down.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}
