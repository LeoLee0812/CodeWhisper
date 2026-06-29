//
//  HistoryView.swift
//  CodeWhisper
//
//  历史记录列表：展示全部转录记录（文本 + 相对时间），
//  点击行复制、右键 / swipe 删除，顶部「清空」按钮。
//  数据只读自 HistoryStore（@EnvironmentObject）。
//
//  修改记录：
//  - 朱菜：初版创建。List + RelativeDateTimeFormatter；删除调 history.remove，清空调 history.clear。
//

import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    /// 关闭 sheet（当作为 sheet 弹出时使用）。
    @Environment(\.dismiss) private var dismiss

    /// 复制反馈。
    @State private var copiedFlash = false

    /// 相对时间格式器（如「3 分钟前」）。
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: - 顶部栏

    private var header: some View {
        HStack {
            Text("转录历史")
                .font(.headline)
            if copiedFlash {
                Text("已复制").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button(role: .destructive) {
                history.clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(history.records.isEmpty)

            Button("完成") { dismiss() }
                .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - 列表内容

    @ViewBuilder private var content: some View {
        if history.records.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("还没有历史记录")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(history.records) { record in
                    rowView(record)
                }
                .onDelete(perform: deleteAt)
            }
            .listStyle(.inset)
        }
    }

    /// 单条记录行。
    private func rowView(_ record: HistoryRecord) -> some View {
        Button {
            ClipboardManager.copy(record.text)
            flashCopied()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.callout)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(Self.relativeFormatter.localizedString(for: record.createdAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击复制")
        .contextMenu {
            Button {
                ClipboardManager.copy(record.text)
                flashCopied()
            } label: { Label("复制", systemImage: "doc.on.doc") }
            Button(role: .destructive) {
                history.remove(record)
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    /// swipe 删除：按索引映射到记录。
    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets {
            history.remove(history.records[index])
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
