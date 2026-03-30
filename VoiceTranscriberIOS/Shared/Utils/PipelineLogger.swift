import Foundation
import os

/// Logs pipeline timing data for performance analysis.
/// Writes to os_log (visible in Console.app) and a CSV file in the App Group container.
final class PipelineLogger {
    static let shared = PipelineLogger()

    private let logger = Logger(subsystem: "com.verbalize.ios", category: "pipeline")
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.verbalize.pipelinelogger")

    private init() {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = container.appendingPathComponent("pipeline_timing.csv")

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

        if let error = error {
            logger.error("[\(engine)/\(sttModel)] FAILED after \(total)ms — \(error)")
        } else {
            logger.info("[\(engine)/\(sttModel)] transcribe=\(transcribeMs)ms cleanup=\(cleanupMs)ms (\(cleanupMethod)/\(cleanupModel)) total=\(total)ms | \(String(format: "%.1f", audioDuration))s audio → \(wordCount) words")
        }

        queue.async { [fileURL] in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let escapedError = (error ?? "").replacingOccurrences(of: ",", with: ";")
            let line = "\(timestamp),\(engine),\(sttModel),\(transcribeMs),\(cleanupMs),\(cleanupMethod),\(cleanupModel),\(String(format: "%.1f", audioDuration)),\(wordCount),\(total),\(escapedError)\n"
            if let data = line.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }
}
