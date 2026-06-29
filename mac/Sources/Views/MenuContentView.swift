//
//  MenuContentView.swift
//  CodeWhisper
//
//  菜单栏弹窗主面板（窗口风格，宽约 320）。
//  顶部状态行 + 电平动效、热键提示、大录音按钮、最近结果、最近历史预览、底部操作行。
//  无辅助功能权限时顶部给黄色提示条 + 去授权按钮。
//  所有状态只读自 AppState/AppSettings/HistoryStore。
//
//  修改记录：
//  - 朱菜：初版创建。AppState 契约消费；电平条用 audioLevel 绘制；prepareModel 在 .task 中触发。
//  - 朱菜：新增流式实时字幕区 liveTranscriptSection，仅在「流式模式 + 正在录音 + lastText 非空」时显示，
//          随 @Published lastText 自动刷新。既有 lastResultSection/historyPreviewSection 显示条件不变。
//  - 朱菜：lastResultSection 显示条件加非录音守卫（phase != .recording），消除录音中「实时转录」
//          与「最近结果」同段文本重复；liveTranscriptSection / historyPreviewSection 条件不变。
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryStore

    /// 是否已获得辅助功能权限（用于决定是否显示授权提示条）。
    @State private var hasAxPermission: Bool = ClipboardManager.hasAccessibilityPermission()
    /// 控制历史全列表 sheet 的显示。
    @State private var showHistory = false
    /// 复制反馈：短暂提示「已复制」。
    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !hasAxPermission {
                permissionBanner
            }

            statusRow

            hotKeyHint

            recordButton

            // 流式模式录音过程中的实时字幕（边说边出字反馈）。
            if isStreamingLive {
                liveTranscriptSection
            }

            // 录音中只显示「实时转录」，松开定稿回到 .ready/.transcribing 后再显示「最近结果」，避免文本重复。
            if !appState.lastText.isEmpty && appState.phase != .recording {
                lastResultSection
            }

            if !history.records.isEmpty {
                historyPreviewSection
            }

            Divider()

            footerButtons
        }
        .padding(14)
        .frame(width: 320)
        .task {
            // 首次打开时确保模型已准备（下载 + 加载）。幂等由 Core 保证。
            await appState.prepareModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 应用重新激活时刷新权限状态（用户可能刚在系统设置里授权）。
            hasAxPermission = ClipboardManager.hasAccessibilityPermission()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(history)
                .frame(width: 380, height: 460)
        }
    }

    // MARK: - 顶部标题

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.tint)
            Text("CodeWhisper")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - 辅助功能权限提示条

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("未获得辅助功能权限")
                    .font(.caption.bold())
                Text("自动粘贴与全局热键需要此权限。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("去授权") {
                    ClipboardManager.requestAccessibilityPermission()
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 状态行（含电平动效 / 进度）

    private var statusRow: some View {
        HStack(spacing: 10) {
            switch appState.phase {
            case .idle, .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("就绪").font(.subheadline)
            case .recording:
                AudioLevelMeter(level: appState.audioLevel)
                Text("正在录音…").font(.subheadline).foregroundStyle(.red)
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("转录中…").font(.subheadline)
            case .downloadingModel(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载模型 \(Int(progress * 100))%").font(.subheadline)
                    ProgressView(value: progress)
                }
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .frame(minHeight: 28)
    }

    // MARK: - 热键提示

    private var hotKeyHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            Text("按住 \(settings.hotKeyDescription) 录音")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 大录音按钮

    private var recordButton: some View {
        Button {
            appState.toggleRecording()
        } label: {
            HStack {
                Image(systemName: appState.phase == .recording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                Text(appState.phase == .recording ? "停止并转录" : "开始录音")
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.phase == .recording ? .red : .accentColor)
        // 下载中禁用录音入口。
        .disabled(isDownloading)
    }

    /// 是否处于模型下载阶段。
    private var isDownloading: Bool {
        if case .downloadingModel = appState.phase { return true }
        return false
    }

    // MARK: - 流式实时字幕

    /// 是否应展示流式实时字幕：流式模式 + 正在录音 + 已有预览文本。
    private var isStreamingLive: Bool {
        settings.transcriptionMode == .streaming
            && appState.phase == .recording
            && !appState.lastText.isEmpty
    }

    /// 实时转录字幕区：样式参考 lastResultSection，圆角浅底、限 4 行。
    private var liveTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("实时转录").font(.caption.bold()).foregroundStyle(.secondary)
            Text(appState.lastText)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 最近结果

    private var lastResultSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近结果").font(.caption.bold()).foregroundStyle(.secondary)
            Button {
                ClipboardManager.copy(appState.lastText)
                flashCopied()
            } label: {
                Text(appState.lastText)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("点击复制")
            if copiedFlash {
                Text("已复制").font(.caption2).foregroundStyle(.green)
            }
        }
    }

    // MARK: - 最近历史预览（最多 3 条）

    private var historyPreviewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近历史").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(history.records.prefix(3)) { record in
                Button {
                    ClipboardManager.copy(record.text)
                    flashCopied()
                } label: {
                    HStack {
                        Text(record.text)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(record.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("点击复制")
            }
        }
    }

    // MARK: - 底部操作行

    private var footerButtons: some View {
        HStack {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .controlSize(.small)

            Button {
                showHistory = true
            } label: {
                Label("历史", systemImage: "clock")
            }
            .controlSize(.small)

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .controlSize(.small)
        }
    }

    /// 显示「已复制」短暂反馈。
    private func flashCopied() {
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedFlash = false
        }
    }
}

/// 录音电平动效：根据 audioLevel(0...1) 绘制几根跳动竖条。
private struct AudioLevelMeter: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    /// 每根竖条高度：中间高、两侧低，并随电平放大。
    private func barHeight(for index: Int) -> CGFloat {
        let mid = Double(barCount - 1) / 2
        let distance = abs(Double(index) - mid)
        let weight = 1.0 - distance / (mid + 1)        // 中间权重大
        let base = 4.0
        let dynamic = Double(max(0, min(1, level))) * 16.0 * weight
        return CGFloat(base + dynamic)
    }
}
