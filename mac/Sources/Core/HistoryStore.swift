import Foundation
import SwiftUI

/// 一条转录历史记录。
struct HistoryRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let text: String
    let createdAt: Date
}

/// 转录历史持久化（JSON 存于 Application Support，容量受限）。
/// 对应 Python 版 history_manager.HistoryManager。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [HistoryRecord] = []

    private let maxRecords: Int
    private let fileURL: URL

    init(maxRecords: Int = 50) {
        self.maxRecords = maxRecords
        self.fileURL = AppPaths.supportDirectory().appendingPathComponent("history.json")
        load()
    }

    func add(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        records.insert(HistoryRecord(text: cleaned, createdAt: Date()), at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func clear() {
        records = []
        save()
    }

    func remove(_ record: HistoryRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.cw.decode([HistoryRecord].self, from: data) else {
            return
        }
        records = Array(decoded.prefix(maxRecords))
    }

    private func save() {
        guard let data = try? JSONEncoder.cw.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var cw: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }
}

extension JSONDecoder {
    static var cw: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
