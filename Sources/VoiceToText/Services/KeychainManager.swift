import Foundation
import Security
import CryptoKit

enum KeychainManager {

    private static let service = "com.voicetotext.apikeys"
    private static let deepseekAccount = "deepseek_api_key"
    private static let bigModelAccount = "bigmodel_api_key"
    private static let encryptionKeyAccount = "encryption_master_key"
    private static let queue = DispatchQueue(label: "com.voicetotext.keychain")

    // MARK: - API Keys

    static var deepseekAPIKey: String? {
        get { read(account: deepseekAccount) }
        set { write(account: deepseekAccount, value: newValue ?? "") }
    }

    static var bigModelAPIKey: String? {
        get { read(account: bigModelAccount) }
        set { write(account: bigModelAccount, value: newValue ?? "") }
    }

    // MARK: - Encryption Key

    static func getOrCreateEncryptionKey() -> SymmetricKey {
        queue.sync {
            if let data = _readData(account: encryptionKeyAccount), data.count == Limits.aes256KeySize {
                return SymmetricKey(data: data)
            }
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            _writeData(account: encryptionKeyAccount, data: keyData)
            return key
        }
    }

    // MARK: - Internal

    static func read(account: String) -> String? {
        queue.sync {
            guard let data = _readData(account: account) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    static func write(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        queue.sync {
            _writeData(account: account, data: data)
        }
    }

    /// Must be called within `queue.sync`.
    private static func _readData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// Must be called within `queue.sync`.
    private static func _writeData(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status != errSecSuccess {
                print("[Keychain] Failed to update \(account): \(status)")
            }
        } else {
            var newItem = query
            newItem[kSecValueData as String] = data
            let status = SecItemAdd(newItem as CFDictionary, nil)
            if status != errSecSuccess {
                print("[Keychain] Failed to add \(account): \(status)")
            }
        }
    }
}
