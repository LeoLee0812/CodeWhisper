import Foundation
import OSLog

/// 轻量日志封装，统一走 os.Logger（可在 Console.app 查看），对应 Python 版的 console 模块。
enum CWLog {
    private static let logger = Logger(subsystem: "com.codewhisper.app", category: "core")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    static func warn(_ message: String) { logger.warning("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}
