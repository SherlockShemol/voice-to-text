import XCTest
import CryptoKit
@testable import VoiceToText

final class EncryptionServiceTests: XCTestCase {

    private var sut: EncryptionService!

    override func setUp() {
        super.setUp()
        sut = EncryptionService(key: SymmetricKey(size: .bits256))
    }

    // MARK: - Data round-trip

    func testEncryptDecryptData() throws {
        let original = Data("Hello, 世界!".utf8)
        let cipher = try sut.encrypt(original)
        let decrypted = try sut.decrypt(cipher)
        XCTAssertEqual(decrypted, original)
    }

    func testEncryptDecryptEmptyData() throws {
        let original = Data()
        let cipher = try sut.encrypt(original)
        let decrypted = try sut.decrypt(cipher)
        XCTAssertEqual(decrypted, original)
    }

    func testEncryptDecryptLargeData() throws {
        let original = Data(repeating: 0xAB, count: 1_000_000)
        let cipher = try sut.encrypt(original)
        let decrypted = try sut.decrypt(cipher)
        XCTAssertEqual(decrypted, original)
    }

    // MARK: - String round-trip

    func testEncryptDecryptString() throws {
        let original = "按住 Fn 键开始语音输入"
        let cipher = try sut.encrypt(string: original)
        let decrypted = try sut.decryptString(from: cipher)
        XCTAssertEqual(decrypted, original)
    }

    func testEncryptDecryptEmptyString() throws {
        let cipher = try sut.encrypt(string: "")
        let decrypted = try sut.decryptString(from: cipher)
        XCTAssertEqual(decrypted, "")
    }

    // MARK: - Ciphertext properties

    func testCiphertextDiffersFromPlaintext() throws {
        let original = Data("secret".utf8)
        let cipher = try sut.encrypt(original)
        XCTAssertNotEqual(cipher, original)
    }

    func testCiphertextLongerThanPlaintext() throws {
        let original = Data("test".utf8)
        let cipher = try sut.encrypt(original)
        // AES-GCM adds 12 bytes nonce + 16 bytes tag = 28 bytes overhead
        XCTAssertEqual(cipher.count, original.count + 28)
    }

    func testEachEncryptionProducesUniqueCiphertext() throws {
        let original = Data("same input".utf8)
        let cipher1 = try sut.encrypt(original)
        let cipher2 = try sut.encrypt(original)
        XCTAssertNotEqual(cipher1, cipher2, "Nonce should make each ciphertext unique")

        // But both decrypt to the same thing
        XCTAssertEqual(try sut.decrypt(cipher1), try sut.decrypt(cipher2))
    }

    // MARK: - Wrong key

    func testDecryptWithWrongKeyFails() throws {
        let cipher = try sut.encrypt(Data("secret".utf8))

        let wrongKey = EncryptionService(key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrongKey.decrypt(cipher))
    }

    // MARK: - Tampered data

    func testDecryptTamperedDataFails() throws {
        var cipher = try sut.encrypt(Data("important".utf8))
        // Flip a byte in the middle of the ciphertext
        let idx = cipher.count / 2
        cipher[idx] ^= 0xFF
        XCTAssertThrowsError(try sut.decrypt(cipher))
    }

    func testDecryptTruncatedDataFails() throws {
        let cipher = try sut.encrypt(Data("data".utf8))
        let truncated = cipher.prefix(cipher.count - 1)
        XCTAssertThrowsError(try sut.decrypt(Data(truncated)))
    }
}
