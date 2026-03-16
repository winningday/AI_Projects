import Foundation
import GRDB

/// Manages local SQLite storage for transcript history using GRDB.
final class TranscriptDatabase: ObservableObject {
    static let shared = TranscriptDatabase()

    private var dbQueue: DatabaseQueue?
    @Published var transcripts: [Transcript] = []

    private init() {
        do {
            try setupDatabase()
            try loadTranscripts()
        } catch {
            print("Database initialization error: \(error)")
        }
    }

    // MARK: - Setup

    private func setupDatabase() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Try new name first, fall back to old name for migration
        let newDir = appSupport.appendingPathComponent("Verbalize", isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("VoiceTranscriber", isDirectory: true)

        // Migrate from old directory if it exists and new one doesn't
        if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: newDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }

        let appDir = newDir

        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbPath = appDir.appendingPathComponent("transcripts.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)

        try dbQueue?.write { db in
            try db.create(table: "transcript", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("originalText", .text).notNull()
                t.column("cleanedText", .text).notNull()
                t.column("durationSeconds", .double).notNull()
            }

            // Migration: add correctedText column (v1.3)
            if try !db.columns(in: "transcript").contains(where: { $0.name == "correctedText" }) {
                try db.alter(table: "transcript") { t in
                    t.add(column: "correctedText", .text)
                }
            }
        }
    }

    // MARK: - CRUD

    func save(_ transcript: Transcript) throws {
        try dbQueue?.write { db in
            try TranscriptRecord(from: transcript).insert(db)
        }
        DispatchQueue.main.async {
            self.transcripts.insert(transcript, at: 0)
        }
    }

    func loadTranscripts() throws {
        let records = try dbQueue?.read { db in
            try TranscriptRecord
                .order(Column("timestamp").desc)
                .fetchAll(db)
        } ?? []

        DispatchQueue.main.async {
            self.transcripts = records.map { $0.toTranscript() }
        }
    }

    func delete(_ transcript: Transcript) throws {
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM transcript WHERE id = ?", arguments: [transcript.id.uuidString])
        }
        DispatchQueue.main.async {
            self.transcripts.removeAll { $0.id == transcript.id }
        }
    }

    func updateCorrectedText(_ correctedText: String, for transcript: Transcript) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE transcript SET correctedText = ? WHERE id = ?",
                arguments: [correctedText, transcript.id.uuidString]
            )
        }
        DispatchQueue.main.async {
            if let index = self.transcripts.firstIndex(where: { $0.id == transcript.id }) {
                self.transcripts[index].correctedText = correctedText
            }
        }
    }

    func deleteAll() throws {
        try dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM transcript")
        }
        DispatchQueue.main.async {
            self.transcripts = []
        }
    }

    func search(query: String) throws -> [Transcript] {
        let records = try dbQueue?.read { db in
            try TranscriptRecord
                .filter(Column("originalText").like("%\(query)%") || Column("cleanedText").like("%\(query)%"))
                .order(Column("timestamp").desc)
                .fetchAll(db)
        } ?? []

        return records.map { $0.toTranscript() }
    }
}

// MARK: - GRDB Record

private struct TranscriptRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript"

    let id: String
    let timestamp: Date
    let originalText: String
    let cleanedText: String
    let durationSeconds: Double
    let correctedText: String?

    init(from transcript: Transcript) {
        self.id = transcript.id.uuidString
        self.timestamp = transcript.timestamp
        self.originalText = transcript.originalText
        self.cleanedText = transcript.cleanedText
        self.durationSeconds = transcript.durationSeconds
        self.correctedText = transcript.correctedText
    }

    func toTranscript() -> Transcript {
        Transcript(
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: timestamp,
            originalText: originalText,
            cleanedText: cleanedText,
            durationSeconds: durationSeconds,
            correctedText: correctedText
        )
    }
}
