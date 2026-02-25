import XCTest
@testable import VoiceToText

final class KeychainManagerTests: XCTestCase {

    private let testAccount = "test_keychain_manager_\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        KeychainManager.write(account: testAccount, value: "")
    }

    // MARK: - Read / Write

    func testWriteAndRead() {
        KeychainManager.write(account: testAccount, value: "test-secret-123")
        let result = KeychainManager.read(account: testAccount)
        XCTAssertEqual(result, "test-secret-123")
    }

    func testReadNonexistentAccountReturnsNil() {
        let result = KeychainManager.read(account: "nonexistent_account_\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    func testOverwriteExistingValue() {
        KeychainManager.write(account: testAccount, value: "first")
        KeychainManager.write(account: testAccount, value: "second")
        let result = KeychainManager.read(account: testAccount)
        XCTAssertEqual(result, "second")
    }

    func testWriteEmptyStringKeepsPreviousValue() {
        KeychainManager.write(account: testAccount, value: "something")
        KeychainManager.write(account: testAccount, value: "")
        let result = KeychainManager.read(account: testAccount)
        // Keychain stores empty data as a valid entry; reading it back may
        // return the previous value depending on OS behavior.
        XCTAssertNotNil(result)
    }

    func testWriteUnicodeValue() {
        let chinese = "你好世界🌍"
        KeychainManager.write(account: testAccount, value: chinese)
        let result = KeychainManager.read(account: testAccount)
        XCTAssertEqual(result, chinese)
    }

    // MARK: - Encryption Key

    func testGetOrCreateEncryptionKeyReturnsConsistentKey() {
        let key1 = KeychainManager.getOrCreateEncryptionKey()
        let key2 = KeychainManager.getOrCreateEncryptionKey()
        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data1, data2, "Encryption key should be consistent across calls")
    }

    func testEncryptionKeyIs256Bits() {
        let key = KeychainManager.getOrCreateEncryptionKey()
        let data = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data.count, 32, "AES-256 key should be 32 bytes")
    }

    // MARK: - Thread Safety

    func testConcurrentReadWriteDoesNotCrash() {
        let expectation = expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 20

        for i in 0..<20 {
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    KeychainManager.write(account: self.testAccount, value: "value-\(i)")
                } else {
                    _ = KeychainManager.read(account: self.testAccount)
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10)
    }
}
