import Foundation
import GRDB

struct EncryptedRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcription_records"

    let id: String
    let date: Double

    var encryptedRawText: Data
    var encryptedRefinedText: Data
    var encryptedAudioData: Data?

    var didUseRefinement: Bool
    var transcriptionModel: String?
    var transcriptionTime: Double?
    var refinementModel: String?
    var refinementTime: Double?
    var tokenPrompt: Int?
    var tokenCompletion: Int?
    var tokenTotal: Int?
    var transcriptionCost: Double?
    var refinementCost: Double?
}

final class DatabaseService {

    private let dbQueue: DatabaseQueue

    let databaseURL: URL

    init() throws {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw DatabaseError.directoryNotFound
        }
        let appDir = appSupport.appendingPathComponent("VoiceToText", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        databaseURL = appDir.appendingPathComponent("voicetotext.db")

        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try migrate()
    }

    init(url: URL) throws {
        databaseURL = url
        dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_records") { db in
            try db.create(table: "transcription_records") { t in
                t.primaryKey("id", .text)
                t.column("date", .double).notNull()

                t.column("encryptedRawText", .blob).notNull()
                t.column("encryptedRefinedText", .blob).notNull()
                t.column("encryptedAudioData", .blob)

                t.column("didUseRefinement", .boolean).notNull().defaults(to: false)
                t.column("transcriptionModel", .text)
                t.column("transcriptionTime", .double)
                t.column("refinementModel", .text)
                t.column("refinementTime", .double)
                t.column("tokenPrompt", .integer)
                t.column("tokenCompletion", .integer)
                t.column("tokenTotal", .integer)
                t.column("transcriptionCost", .double)
                t.column("refinementCost", .double)
            }

            try db.create(indexOn: "transcription_records", columns: ["date"])
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - CRUD

    func insert(_ record: EncryptedRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func fetchAll() throws -> [EncryptedRecord] {
        try dbQueue.read { db in
            try EncryptedRecord
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try EncryptedRecord.deleteOne(db, key: id)
        }
    }

    func deleteAll() throws {
        _ = try dbQueue.write { db in
            try EncryptedRecord.deleteAll(db)
        }
    }

    func deleteBefore(date: Double) throws -> Int {
        try dbQueue.write { db in
            try EncryptedRecord
                .filter(Column("date") < date)
                .deleteAll(db)
        }
    }

    // MARK: - Info

    func databaseFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    func recordCount() throws -> Int {
        try dbQueue.read { db in
            try EncryptedRecord.fetchCount(db)
        }
    }
}

enum DatabaseError: LocalizedError {
    case directoryNotFound

    var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Application Support directory not found"
        }
    }
}
