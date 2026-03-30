import Foundation
import os

/// Logs pipeline timing data for performance analysis.
/// Writes both to os_log (visible in Console.app) and to a CSV file in Application Support.
final class PipelineLogger {
    static let shared = PipelineLogger()

    private let logger = Logger(subsystem: "com.verbalize.app", category: "pipeline")
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.verbalize.pipelinelogger")

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Verbalize")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("pipeline_timing.csv")

        // Write CSV header if file doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "timestamp,engine,stt_model,transcribe_ms,cleanup_ms,cleanup_method,cleanup_model,audio_duration_s,word_count,total_ms,error\n"
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func log(
        engine: String,
        sttModel: String = "",
        transcribeMs: Int,
        cleanupMs: Int,
        cleanupMethod: String,
        cleanupModel: String = "",
        audioDuration: Double,
        wordCount: Int,
        totalMs: Int? = nil,
        error: String? = nil
    ) {
        let total = totalMs ?? (transcribeMs + cleanupMs)
        let errorStr = error ?? ""

        // Console log (visible in Console.app with filter "pipeline")
        if let error = error {
            logger.error("[\(engine)/\(sttModel)] FAILED after \(total)ms — \(error)")
        } else {
            logger.info("[\(engine)/\(sttModel)] transcribe=\(transcribeMs)ms cleanup=\(cleanupMs)ms (\(cleanupMethod)/\(cleanupModel)) total=\(total)ms | \(String(format: "%.1f", audioDuration))s audio → \(wordCount) words")
        }

        // CSV append
        queue.async { [fileURL] in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let escapedError = errorStr.replacingOccurrences(of: ",", with: ";")
            let line = "\(timestamp),\(engine),\(sttModel),\(transcribeMs),\(cleanupMs),\(cleanupMethod),\(cleanupModel),\(String(format: "%.1f", audioDuration)),\(wordCount),\(total),\(escapedError)\n"
            if let data = line.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }

    /// Returns the path to the CSV log file for display in settings
    var logFilePath: String {
        fileURL.path
    }

    /// Returns recent log entries as formatted strings for in-app display
    func recentEntries(count: Int = 20) -> [PipelineEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("timestamp") }
        return lines.suffix(count).reversed().compactMap { PipelineEntry(csvLine: $0) }
    }
}

struct PipelineEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let engine: String
    let sttModel: String
    let transcribeMs: Int
    let cleanupMs: Int
    let cleanupMethod: String
    let cleanupModel: String
    let audioDuration: Double
    let wordCount: Int
    let totalMs: Int
    let error: String?

    init?(csvLine: String) {
        let parts = csvLine.components(separatedBy: ",")
        guard parts.count >= 10 else { return nil }
        if let date = ISO8601DateFormatter().date(from: parts[0]) {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm:ss a"
            self.timestamp = fmt.string(from: date)
        } else {
            self.timestamp = parts[0]
        }
        self.engine = parts[1]
        self.sttModel = parts[2]
        self.transcribeMs = Int(parts[3]) ?? 0
        self.cleanupMs = Int(parts[4]) ?? 0
        self.cleanupMethod = parts[5]
        self.cleanupModel = parts[6]
        self.audioDuration = Double(parts[7]) ?? 0
        self.wordCount = Int(parts[8]) ?? 0
        self.totalMs = Int(parts[9]) ?? 0
        self.error = parts.count > 10 && !parts[10].isEmpty ? parts[10] : nil
    }

    var summary: String {
        if let error = error {
            return "[\(engine)] FAILED — \(error)"
        }
        return "[\(engine)/\(sttModel)] \(transcribeMs)ms + \(cleanupMs)ms (\(cleanupMethod)/\(cleanupModel)) = \(totalMs)ms total | \(wordCount) words"
    }
}
