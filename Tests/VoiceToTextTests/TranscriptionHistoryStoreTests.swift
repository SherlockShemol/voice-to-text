import XCTest
import CryptoKit
@testable import VoiceToText

@MainActor
final class TranscriptionHistoryStoreTests: XCTestCase {

    private var sut: TranscriptionHistoryStore!
    private var db: DatabaseService!
    private var enc: EncryptionService!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        db = try! DatabaseService(url: tempURL)
        enc = EncryptionService(key: SymmetricKey(size: .bits256))
        sut = TranscriptionHistoryStore(database: db, encryption: enc)
    }

    override func tearDown() {
        sut = nil
        db = nil
        enc = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("shm"))
        super.tearDown()
    }

    // MARK: - Add Record

    func testAddRecordInsertsAtFront() {
        sut.addRecord(rawText: "first", refinedText: "first", didUseRefinement: false)
        sut.addRecord(rawText: "second", refinedText: "second", didUseRefinement: false)

        XCTAssertEqual(sut.records.count, 2)
        XCTAssertEqual(sut.records[0].rawText, "second")
        XCTAssertEqual(sut.records[1].rawText, "first")
    }

    func testAddRecordPersistsToDatabase() throws {
        sut.addRecord(rawText: "persisted", refinedText: "persisted", didUseRefinement: false)

        let dbRecords = try db.fetchAll()
        XCTAssertEqual(dbRecords.count, 1)

        let decrypted = try enc.decryptString(from: dbRecords[0].encryptedRawText)
        XCTAssertEqual(decrypted, "persisted")
    }

    func testAddRecordWithMetadata() {
        let sttMeta = APICallMetadata(model: "glm-asr", responseTime: 1.5, tokenUsage: nil, cost: 0.003)
        let llmMeta = APICallMetadata(
            model: "deepseek-chat",
            responseTime: 0.8,
            tokenUsage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            cost: 0.001
        )

        sut.addRecord(
            rawText: "raw",
            refinedText: "refined",
            didUseRefinement: true,
            transcriptionMeta: sttMeta,
            refinementMeta: llmMeta,
            audioData: Data([0x00])
        )

        XCTAssertEqual(sut.records.count, 1)
        let record = sut.records[0]
        XCTAssertEqual(record.rawText, "raw")
        XCTAssertEqual(record.refinedText, "refined")
        XCTAssertTrue(record.didUseRefinement)
        XCTAssertTrue(record.hasAudio)
        XCTAssertEqual(record.transcriptionMeta?.model, "glm-asr")
        XCTAssertEqual(record.refinementMeta?.model, "deepseek-chat")
    }

    // MARK: - Delete Record

    func testDeleteRecordRemovesFromMemoryAndDatabase() throws {
        sut.addRecord(rawText: "keep", refinedText: "keep", didUseRefinement: false)
        sut.addRecord(rawText: "remove", refinedText: "remove", didUseRefinement: false)

        let toRemove = sut.records.first { $0.rawText == "remove" }!
        sut.deleteRecord(toRemove)

        XCTAssertEqual(sut.records.count, 1)
        XCTAssertEqual(sut.records[0].rawText, "keep")

        let dbRecords = try db.fetchAll()
        XCTAssertEqual(dbRecords.count, 1)
    }

    // MARK: - Clear All

    func testClearAllRemovesEverything() throws {
        sut.addRecord(rawText: "a", refinedText: "a", didUseRefinement: false)
        sut.addRecord(rawText: "b", refinedText: "b", didUseRefinement: false)
        sut.addRecord(rawText: "c", refinedText: "c", didUseRefinement: false)

        sut.clearAll()

        XCTAssertTrue(sut.records.isEmpty)
        XCTAssertEqual(try db.fetchAll().count, 0)
    }

    // MARK: - Filtered Records

    func testFilterAll() {
        sut.addRecord(rawText: "a", refinedText: "a", didUseRefinement: false)
        sut.addRecord(rawText: "b", refinedText: "B", didUseRefinement: true)

        let all = sut.filteredRecords(filter: .all)
        XCTAssertEqual(all.count, 2)
    }

    func testFilterTranscribedOnly() {
        sut.addRecord(rawText: "a", refinedText: "a", didUseRefinement: false)
        sut.addRecord(rawText: "b", refinedText: "B", didUseRefinement: true)
        sut.addRecord(rawText: "c", refinedText: "c", didUseRefinement: false)

        let filtered = sut.filteredRecords(filter: .transcribedOnly)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { !$0.didUseRefinement })
    }

    func testFilterRefinedOnly() {
        sut.addRecord(rawText: "a", refinedText: "a", didUseRefinement: false)
        sut.addRecord(rawText: "b", refinedText: "B", didUseRefinement: true)
        sut.addRecord(rawText: "c", refinedText: "C", didUseRefinement: true)

        let filtered = sut.filteredRecords(filter: .refinedOnly)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.didUseRefinement })
    }

    func testFilterEmptyRecords() {
        XCTAssertTrue(sut.filteredRecords(filter: .all).isEmpty)
        XCTAssertTrue(sut.filteredRecords(filter: .transcribedOnly).isEmpty)
        XCTAssertTrue(sut.filteredRecords(filter: .refinedOnly).isEmpty)
    }

    // MARK: - Records Grouped by Date

    func testRecordsGroupedByDateSortedDescending() {
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)

        sut.records = [
            TranscriptionRecord(date: today, rawText: "today1", refinedText: "today1", didUseRefinement: false),
            TranscriptionRecord(date: today, rawText: "today2", refinedText: "today2", didUseRefinement: false),
            TranscriptionRecord(date: yesterday, rawText: "yesterday", refinedText: "yesterday", didUseRefinement: false),
        ]

        let groups = sut.recordsGroupedByDate(filter: .all)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].1.count, 2, "Today's group should have 2 records")
        XCTAssertEqual(groups[1].1.count, 1, "Yesterday's group should have 1 record")
    }

    func testRecordsGroupedByDateRespectsFilter() {
        let today = Date()

        sut.records = [
            TranscriptionRecord(date: today, rawText: "a", refinedText: "a", didUseRefinement: false),
            TranscriptionRecord(date: today, rawText: "b", refinedText: "B", didUseRefinement: true),
        ]

        let refinedGroups = sut.recordsGroupedByDate(filter: .refinedOnly)
        let totalRecords = refinedGroups.flatMap { $0.1 }
        XCTAssertEqual(totalRecords.count, 1)
        XCTAssertTrue(totalRecords[0].didUseRefinement)
    }

    // MARK: - Retention & Pruning

    func testSetRetentionUpdatesProperty() {
        sut.setRetention(.oneWeek)
        XCTAssertEqual(sut.retention, .oneWeek)
    }

    func testPruneExpiredRemovesOldRecords() {
        let old = Date().addingTimeInterval(-86400 * 10) // 10 days ago
        let recent = Date()

        sut.records = [
            TranscriptionRecord(date: old, rawText: "old", refinedText: "old", didUseRefinement: false),
            TranscriptionRecord(date: recent, rawText: "new", refinedText: "new", didUseRefinement: false),
        ]

        sut.setRetention(.oneWeek)

        XCTAssertEqual(sut.records.count, 1)
        XCTAssertEqual(sut.records[0].rawText, "new")
    }

    func testPruneExpiredKeepsAllWhenForever() {
        let veryOld = Date().addingTimeInterval(-86400 * 365)

        sut.records = [
            TranscriptionRecord(date: veryOld, rawText: "ancient", refinedText: "ancient", didUseRefinement: false),
        ]

        sut.setRetention(.forever)

        XCTAssertEqual(sut.records.count, 1)
    }

    func testPruneExpiredOneDayRetention() {
        let twoDaysAgo = Date().addingTimeInterval(-86400 * 2)
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)

        sut.records = [
            TranscriptionRecord(date: twoDaysAgo, rawText: "old", refinedText: "old", didUseRefinement: false),
            TranscriptionRecord(date: thirtyMinutesAgo, rawText: "recent", refinedText: "recent", didUseRefinement: false),
        ]

        sut.setRetention(.oneDay)

        XCTAssertEqual(sut.records.count, 1)
        XCTAssertEqual(sut.records[0].rawText, "recent")
    }

    // MARK: - Database File Size

    func testDatabaseFileSizeIsNonNegative() {
        XCTAssertGreaterThanOrEqual(sut.databaseFileSize, 0)
    }

    func testDatabaseFileSizeGrowsAfterInsert() {
        let sizeBefore = sut.databaseFileSize
        sut.addRecord(rawText: "test", refinedText: "test", didUseRefinement: false)
        let sizeAfter = sut.databaseFileSize
        XCTAssertGreaterThanOrEqual(sizeAfter, sizeBefore)
    }

    // MARK: - Load from database

    func testRecordsLoadedFromDatabaseOnInit() throws {
        sut.addRecord(rawText: "loaded", refinedText: "loaded text", didUseRefinement: false)
        let id = sut.records[0].id

        let sut2 = TranscriptionHistoryStore(database: db, encryption: enc)
        XCTAssertEqual(sut2.records.count, 1)
        XCTAssertEqual(sut2.records[0].id, id)

        let decrypted = sut2.records[0].rawText
        XCTAssertEqual(decrypted, "loaded")
    }

    // MARK: - Encrypt/Decrypt round-trip via store

    func testAddAndReloadPreservesAllFields() throws {
        let sttMeta = APICallMetadata(model: "glm-asr-2512", responseTime: 1.5, tokenUsage: nil, cost: 0.003)
        let llmMeta = APICallMetadata(
            model: "deepseek-chat",
            responseTime: 0.8,
            tokenUsage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            cost: 0.001
        )

        sut.addRecord(
            rawText: "原始",
            refinedText: "润色后",
            didUseRefinement: true,
            transcriptionMeta: sttMeta,
            refinementMeta: llmMeta,
            audioData: Data([0xAA, 0xBB])
        )

        let reloaded = TranscriptionHistoryStore(database: db, encryption: enc)
        XCTAssertEqual(reloaded.records.count, 1)

        let r = reloaded.records[0]
        XCTAssertEqual(r.rawText, "原始")
        XCTAssertEqual(r.refinedText, "润色后")
        XCTAssertTrue(r.didUseRefinement)
        XCTAssertEqual(r.transcriptionMeta?.model, "glm-asr-2512")
        XCTAssertEqual(r.refinementMeta?.model, "deepseek-chat")
        XCTAssertNotNil(r.audioData)
        XCTAssertEqual(r.audioData, Data([0xAA, 0xBB]))
    }
}
