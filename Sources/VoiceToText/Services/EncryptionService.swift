import Foundation
import CryptoKit

struct EncryptionService {

    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    // MARK: - Data

    func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - String convenience

    func encrypt(string: String) throws -> Data {
        try encrypt(Data(string.utf8))
    }

    func decryptString(from data: Data) throws -> String {
        let decrypted = try decrypt(data)
        guard let str = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.invalidUTF8
        }
        return str
    }
}

enum EncryptionError: LocalizedError {
    case sealFailed
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .sealFailed: return "AES-GCM seal returned nil combined data"
        case .invalidUTF8: return "Decrypted data is not valid UTF-8"
        }
    }
}
