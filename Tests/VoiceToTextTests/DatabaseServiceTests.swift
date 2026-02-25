import XCTest
import CryptoKit
@testable import VoiceToText

final class DatabaseServiceTests: XCTestCase {

    private var sut: DatabaseService!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        sut = try! DatabaseService(url: tempURL)
    }

    override func tearDown() {
        sut = nil
        try? FileManager.default.removeItem(at: tempURL)
        // WAL & SHM companion files
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("shm"))
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRecord(
        id: String = UUID().uuidString,
        date: Double = Date().timeIntervalSince1970,
        didUseRefinement: Bool = false,
        audioData: Data? = nil
    ) -> EncryptedRecord {
        EncryptedRecord(
            id: id,
            date: date,
            encryptedRawText: Data("raw".utf8),
            encryptedRefinedText: Data("refined".utf8),
            encryptedAudioData: audioData,
            didUseRefinement: didUseRefinement,
            transcriptionModel: "glm-asr",
            transcriptionTime: 1.5,
            refinementModel: didUseRefinement ? "deepseek" : nil,
            refinementTime: didUseRefinement ? 0.8 : nil,
            tokenPrompt: didUseRefinement ? 50 : nil,
            tokenCompletion: didUseRefinement ? 30 : nil,
            tokenTotal: didUseRefinement ? 80 : nil,
            transcriptionCost: 0.001,
            refinementCost: didUseRefinement ? 0.0002 : nil
        )
    }

    // MARK: - Insert & Fetch

    func testInsertAndFetchSingle() throws {
        let record = makeRecord()
        try sut.insert(record)

        let fetched = try sut.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, record.id)
        XCTAssertEqual(fetched[0].encryptedRawText, record.encryptedRawText)
        XCTAssertEqual(fetched[0].didUseRefinement, record.didUseRefinement)
        XCTAssertEqual(fetched[0].transcriptionModel, "glm-asr")
    }

    func testInsertMultipleAndFetchOrderByDateDesc() throws {
        let older = makeRecord(id: "A", date: 1000)
        let newer = makeRecord(id: "B", date: 2000)
        try sut.insert(older)
        try sut.insert(newer)

        let fetched = try sut.fetchAll()
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].id, "B", "Newer record should come first")
        XCTAssertEqual(fetched[1].id, "A")
    }

    func testInsertWithAudioData() throws {
        let audio = Data(repeating: 0xAA, count: 1024)
        let record = makeRecord(audioData: audio)
        try sut.insert(record)

        let fetched = try sut.fetchAll()
        XCTAssertEqual(fetched[0].encryptedAudioData, audio)
    }

    func testInsertWithoutAudioData() throws {
        let record = makeRecord(audioData: nil)
        try sut.insert(record)

        let fetched = try sut.fetchAll()
        XCTAssertNil(fetched[0].encryptedAudioData)
    }

    func testInsertWithRefinementMetadata() throws {
        let record = makeRecord(didUseRefinement: true)
        try sut.insert(record)

        let fetched = try sut.fetchAll()
        XCTAssertTrue(fetched[0].didUseRefinement)
        XCTAssertEqual(fetched[0].refinementModel, "deepseek")
        XCTAssertEqual(fetched[0].tokenTotal, 80)
    }

    // MARK: - Delete

    func testDeleteById() throws {
        let r1 = makeRecord(id: "keep")
        let r2 = makeRecord(id: "remove")
        try sut.insert(r1)
        try sut.insert(r2)

        try sut.delete(id: "remove")

        let fetched = try sut.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "keep")
    }

    func testDeleteNonExistentIdDoesNotThrow() throws {
        try sut.insert(makeRecord())
        XCTAssertNoThrow(try sut.delete(id: "nonexistent"))
        XCTAssertEqual(try sut.fetchAll().count, 1)
    }

    func testDeleteAll() throws {
        for _ in 0..<5 {
            try sut.insert(makeRecord())
        }
        XCTAssertEqual(try sut.fetchAll().count, 5)

        try sut.deleteAll()
        XCTAssertEqual(try sut.fetchAll().count, 0)
    }

    // MARK: - Delete before date

    func testDeleteBeforeDate() throws {
        try sut.insert(makeRecord(id: "old1", date: 100))
        try sut.insert(makeRecord(id: "old2", date: 200))
        try sut.insert(makeRecord(id: "new1", date: 500))
        try sut.insert(makeRecord(id: "new2", date: 600))

        let deleted = try sut.deleteBefore(date: 300)

        XCTAssertEqual(deleted, 2)
        let remaining = try sut.fetchAll()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.allSatisfy { $0.date >= 500 })
    }

    func testDeleteBeforeDateNoMatch() throws {
        try sut.insert(makeRecord(date: 1000))
        let deleted = try sut.deleteBefore(date: 500)
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(try sut.fetchAll().count, 1)
    }

    // MARK: - Record count

    func testRecordCount() throws {
        XCTAssertEqual(try sut.recordCount(), 0)
        try sut.insert(makeRecord())
        try sut.insert(makeRecord())
        try sut.insert(makeRecord())
        XCTAssertEqual(try sut.recordCount(), 3)
    }

    // MARK: - Database file

    func testDatabaseFileExists() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testDatabaseFileSizeGrowsWithData() throws {
        let sizeBefore = sut.databaseFileSize()
        let largeAudio = Data(repeating: 0xFF, count: 50_000)
        try sut.insert(makeRecord(audioData: largeAudio))
        let sizeAfter = sut.databaseFileSize()
        XCTAssertGreaterThan(sizeAfter, sizeBefore)
    }

    // MARK: - Duplicate primary key

    func testInsertDuplicateIdThrows() throws {
        let record = makeRecord(id: "dup")
        try sut.insert(record)
        XCTAssertThrowsError(try sut.insert(record))
    }

    // MARK: - Persistence across instances

    func testDataPersistsAcrossInstances() throws {
        let record = makeRecord(id: "persist-test")
        try sut.insert(record)

        let sut2 = try DatabaseService(url: tempURL)
        let fetched = try sut2.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "persist-test")
    }
}
