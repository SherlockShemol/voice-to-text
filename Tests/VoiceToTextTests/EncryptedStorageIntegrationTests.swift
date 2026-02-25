import XCTest
import CryptoKit
@testable import VoiceToText

/// End-to-end tests: plaintext -> encrypt -> store in DB -> fetch -> decrypt -> verify
final class EncryptedStorageIntegrationTests: XCTestCase {

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
    }

    override func tearDown() {
        db = nil
        enc = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("shm"))
        super.tearDown()
    }

    // MARK: - Full round-trip: text only

    func testTextOnlyRoundTrip() throws {
        let rawText = "你好，这是一个测试"
        let refinedText = "你好，这是一个经过润色的测试。"
        let id = UUID()

        let encRaw = try enc.encrypt(string: rawText)
        let encRefined = try enc.encrypt(string: refinedText)

        let record = EncryptedRecord(
            id: id.uuidString,
            date: Date().timeIntervalSince1970,
            encryptedRawText: encRaw,
            encryptedRefinedText: encRefined,
            encryptedAudioData: nil,
            didUseRefinement: true,
            transcriptionModel: "glm-asr-2512",
            transcriptionTime: 1.2,
            refinementModel: "deepseek-chat",
            refinementTime: 0.5,
            tokenPrompt: 100,
            tokenCompletion: 60,
            tokenTotal: 160,
            transcriptionCost: 0.003,
            refinementCost: 0.0005
        )

        try db.insert(record)

        let fetched = try db.fetchAll()
        XCTAssertEqual(fetched.count, 1)

        let f = fetched[0]
        XCTAssertEqual(f.id, id.uuidString)
        XCTAssertTrue(f.didUseRefinement)
        XCTAssertEqual(f.transcriptionModel, "glm-asr-2512")
        XCTAssertEqual(f.refinementModel, "deepseek-chat")
        XCTAssertEqual(f.tokenTotal, 160)

        // Encrypted blobs are NOT the original plaintext
        XCTAssertNotEqual(f.encryptedRawText, Data(rawText.utf8))
        XCTAssertNotEqual(f.encryptedRefinedText, Data(refinedText.utf8))

        // Decrypt and verify
        let decRaw = try enc.decryptString(from: f.encryptedRawText)
        let decRefined = try enc.decryptString(from: f.encryptedRefinedText)
        XCTAssertEqual(decRaw, rawText)
        XCTAssertEqual(decRefined, refinedText)
        XCTAssertNil(f.encryptedAudioData)
    }

    // MARK: - Full round-trip: text + audio

    func testTextAndAudioRoundTrip() throws {
        let rawText = "audio test"
        let refinedText = "Audio test with refinement."
        let fakeAudio = Data((0..<960_000).map { UInt8($0 & 0xFF) })

        let encRaw = try enc.encrypt(string: rawText)
        let encRefined = try enc.encrypt(string: refinedText)
        let encAudio = try enc.encrypt(fakeAudio)

        let record = EncryptedRecord(
            id: UUID().uuidString,
            date: Date().timeIntervalSince1970,
            encryptedRawText: encRaw,
            encryptedRefinedText: encRefined,
            encryptedAudioData: encAudio,
            didUseRefinement: false,
            transcriptionModel: "glm-asr",
            transcriptionTime: 2.0,
            refinementModel: nil,
            refinementTime: nil,
            tokenPrompt: nil,
            tokenCompletion: nil,
            tokenTotal: nil,
            transcriptionCost: 0.002,
            refinementCost: nil
        )

        try db.insert(record)
        let fetched = try db.fetchAll()
        XCTAssertEqual(fetched.count, 1)

        let f = fetched[0]
        let decRaw = try enc.decryptString(from: f.encryptedRawText)
        let decRefined = try enc.decryptString(from: f.encryptedRefinedText)
        let decAudio = try enc.decrypt(f.encryptedAudioData!)

        XCTAssertEqual(decRaw, rawText)
        XCTAssertEqual(decRefined, refinedText)
        XCTAssertEqual(decAudio, fakeAudio)
    }

    // MARK: - Wrong key cannot decrypt stored data

    func testWrongKeyCannotDecryptStoredData() throws {
        let secret = "机密信息"
        let encData = try enc.encrypt(string: secret)

        let record = EncryptedRecord(
            id: UUID().uuidString,
            date: Date().timeIntervalSince1970,
            encryptedRawText: encData,
            encryptedRefinedText: encData,
            encryptedAudioData: nil,
            didUseRefinement: false,
            transcriptionModel: nil,
            transcriptionTime: nil,
            refinementModel: nil,
            refinementTime: nil,
            tokenPrompt: nil,
            tokenCompletion: nil,
            tokenTotal: nil,
            transcriptionCost: nil,
            refinementCost: nil
        )

        try db.insert(record)
        let fetched = try db.fetchAll()

        let wrongEnc = EncryptionService(key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrongEnc.decryptString(from: fetched[0].encryptedRawText))
    }

    // MARK: - Multiple records CRUD with encryption

    func testMultipleRecordsCRUD() throws {
        let texts = ["第一条", "第二条", "第三条"]
        var ids: [String] = []

        for (i, text) in texts.enumerated() {
            let id = UUID().uuidString
            ids.append(id)
            let record = EncryptedRecord(
                id: id,
                date: Double(i) * 100,
                encryptedRawText: try enc.encrypt(string: text),
                encryptedRefinedText: try enc.encrypt(string: text),
                encryptedAudioData: nil,
                didUseRefinement: false,
                transcriptionModel: nil,
                transcriptionTime: nil,
                refinementModel: nil,
                refinementTime: nil,
                tokenPrompt: nil,
                tokenCompletion: nil,
                tokenTotal: nil,
                transcriptionCost: nil,
                refinementCost: nil
            )
            try db.insert(record)
        }

        XCTAssertEqual(try db.recordCount(), 3)

        // Delete middle record
        try db.delete(id: ids[1])
        XCTAssertEqual(try db.recordCount(), 2)

        // Verify remaining decryption
        let remaining = try db.fetchAll()
        let decryptedTexts = try remaining.map { try enc.decryptString(from: $0.encryptedRawText) }
        XCTAssertTrue(decryptedTexts.contains("第一条"))
        XCTAssertFalse(decryptedTexts.contains("第二条"))
        XCTAssertTrue(decryptedTexts.contains("第三条"))

        // Delete all
        try db.deleteAll()
        XCTAssertEqual(try db.recordCount(), 0)
    }

    // MARK: - Metadata preserved in cleartext

    func testMetadataStoredInCleartext() throws {
        let record = EncryptedRecord(
            id: UUID().uuidString,
            date: 1700000000.0,
            encryptedRawText: try enc.encrypt(string: "test"),
            encryptedRefinedText: try enc.encrypt(string: "test"),
            encryptedAudioData: nil,
            didUseRefinement: true,
            transcriptionModel: "glm-asr-2512",
            transcriptionTime: 1.23,
            refinementModel: "deepseek-chat",
            refinementTime: 0.45,
            tokenPrompt: 120,
            tokenCompletion: 80,
            tokenTotal: 200,
            transcriptionCost: 0.003,
            refinementCost: 0.001
        )
        try db.insert(record)

        let f = try db.fetchAll()[0]
        XCTAssertEqual(f.date, 1700000000.0, accuracy: 0.001)
        XCTAssertEqual(f.transcriptionModel, "glm-asr-2512")
        XCTAssertEqual(f.transcriptionTime!, 1.23, accuracy: 0.001)
        XCTAssertEqual(f.refinementModel, "deepseek-chat")
        XCTAssertEqual(f.refinementTime!, 0.45, accuracy: 0.001)
        XCTAssertEqual(f.tokenPrompt, 120)
        XCTAssertEqual(f.tokenCompletion, 80)
        XCTAssertEqual(f.tokenTotal, 200)
        XCTAssertEqual(f.transcriptionCost!, 0.003, accuracy: 0.0001)
        XCTAssertEqual(f.refinementCost!, 0.001, accuracy: 0.0001)
    }

    // MARK: - Delete before date with encrypted data

    func testDeleteBeforeDatePreservesEncryptedData() throws {
        let keepText = "keep this"
        try db.insert(EncryptedRecord(
            id: "old", date: 100,
            encryptedRawText: try enc.encrypt(string: "old"),
            encryptedRefinedText: try enc.encrypt(string: "old"),
            encryptedAudioData: nil,
            didUseRefinement: false,
            transcriptionModel: nil, transcriptionTime: nil,
            refinementModel: nil, refinementTime: nil,
            tokenPrompt: nil, tokenCompletion: nil, tokenTotal: nil,
            transcriptionCost: nil, refinementCost: nil
        ))
        try db.insert(EncryptedRecord(
            id: "new", date: 999,
            encryptedRawText: try enc.encrypt(string: keepText),
            encryptedRefinedText: try enc.encrypt(string: keepText),
            encryptedAudioData: nil,
            didUseRefinement: false,
            transcriptionModel: nil, transcriptionTime: nil,
            refinementModel: nil, refinementTime: nil,
            tokenPrompt: nil, tokenCompletion: nil, tokenTotal: nil,
            transcriptionCost: nil, refinementCost: nil
        ))

        let deleted = try db.deleteBefore(date: 500)
        XCTAssertEqual(deleted, 1)

        let remaining = try db.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        let decrypted = try enc.decryptString(from: remaining[0].encryptedRawText)
        XCTAssertEqual(decrypted, keepText)
    }
}
