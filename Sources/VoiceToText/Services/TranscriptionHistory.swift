import Foundation

enum Pricing {
    /// 智谱 GLM-ASR-2512：¥0.06/分钟
    static let sttPricePerMinute: Double = 0.06
    /// Deepseek Chat 输入（缓存未命中）：¥2/百万tokens
    static let llmInputPricePerMillion: Double = 2.0
    /// Deepseek Chat 输出：¥3/百万tokens
    static let llmOutputPricePerMillion: Double = 3.0

    static func sttCost(audioDurationSeconds: TimeInterval) -> Double {
        (audioDurationSeconds / 60.0) * sttPricePerMinute
    }

    static func llmCost(promptTokens: Int, completionTokens: Int) -> Double {
        Double(promptTokens) * llmInputPricePerMillion / 1_000_000
        + Double(completionTokens) * llmOutputPricePerMillion / 1_000_000
    }
}

struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

struct APICallMetadata: Codable {
    let model: String
    let responseTime: TimeInterval
    let tokenUsage: TokenUsage?
    let cost: Double?
}

struct TranscriptionRecord: Identifiable {
    let id: UUID
    let date: Date
    let rawText: String
    let refinedText: String
    let didUseRefinement: Bool
    let transcriptionMeta: APICallMetadata?
    let refinementMeta: APICallMetadata?
    let audioData: Data?

    var displayText: String {
        didUseRefinement ? refinedText : rawText
    }

    var totalCost: Double? {
        let stt = transcriptionMeta?.cost
        let llm = refinementMeta?.cost
        guard stt != nil || llm != nil else { return nil }
        return (stt ?? 0) + (llm ?? 0)
    }

    var hasAudio: Bool { audioData != nil }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        rawText: String,
        refinedText: String,
        didUseRefinement: Bool,
        transcriptionMeta: APICallMetadata? = nil,
        refinementMeta: APICallMetadata? = nil,
        audioData: Data? = nil
    ) {
        self.id = id
        self.date = date
        self.rawText = rawText
        self.refinedText = refinedText
        self.didUseRefinement = didUseRefinement
        self.transcriptionMeta = transcriptionMeta
        self.refinementMeta = refinementMeta
        self.audioData = audioData
    }
}

enum HistoryFilter: String, CaseIterable {
    case all = "全部"
    case transcribedOnly = "仅转录"
    case refinedOnly = "仅润色"
}

enum HistoryRetention: String, CaseIterable, Codable {
    case forever = "永远"
    case oneMonth = "一个月"
    case oneWeek = "一周"
    case oneDay = "一天"

    var timeInterval: TimeInterval? {
        switch self {
        case .forever: return nil
        case .oneMonth: return 30 * 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        case .oneDay: return 24 * 3600
        }
    }
}

// MARK: - Legacy JSON model (for migration only)

private struct LegacyRecord: Codable {
    let id: UUID
    let date: Date
    let rawText: String
    let refinedText: String
    let didUseRefinement: Bool
    let transcriptionMeta: APICallMetadata?
    let refinementMeta: APICallMetadata?
}

// MARK: - Store

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    @Published var records: [TranscriptionRecord] = []
    @Published var retention: HistoryRetention = .forever

    private let database: DatabaseService
    private let encryption: EncryptionService
    private let retentionKey = "historyRetention"

    @Published var databaseError: String?

    init() {
        let key = KeychainManager.getOrCreateEncryptionKey()
        self.encryption = EncryptionService(key: key)

        do {
            self.database = try DatabaseService()
        } catch {
            print("[History] Failed to open database: \(error)")
            self.database = try! DatabaseService(url: FileManager.default.temporaryDirectory.appendingPathComponent("voicetotext_fallback.db"))
            self.databaseError = "数据库初始化失败，使用临时数据库：\(error.localizedDescription)"
        }

        if let saved = UserDefaults.standard.string(forKey: retentionKey),
           let r = HistoryRetention(rawValue: saved) {
            retention = r
        }

        migrateFromJSON()
        loadRecords()
        pruneExpired()
    }

    init(database: DatabaseService, encryption: EncryptionService) {
        self.database = database
        self.encryption = encryption
        loadRecords()
    }

    // MARK: - Public API

    func addRecord(
        rawText: String,
        refinedText: String,
        didUseRefinement: Bool,
        transcriptionMeta: APICallMetadata? = nil,
        refinementMeta: APICallMetadata? = nil,
        audioData: Data? = nil
    ) {
        let record = TranscriptionRecord(
            rawText: rawText,
            refinedText: refinedText,
            didUseRefinement: didUseRefinement,
            transcriptionMeta: transcriptionMeta,
            refinementMeta: refinementMeta,
            audioData: audioData
        )
        records.insert(record, at: 0)
        saveRecord(record)
    }

    func deleteRecord(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        try? database.delete(id: record.id.uuidString)
    }

    func clearAll() {
        records.removeAll()
        try? database.deleteAll()
    }

    func setRetention(_ value: HistoryRetention) {
        retention = value
        UserDefaults.standard.set(value.rawValue, forKey: retentionKey)
        pruneExpired()
    }

    func filteredRecords(filter: HistoryFilter) -> [TranscriptionRecord] {
        switch filter {
        case .all:
            return records
        case .transcribedOnly:
            return records.filter { !$0.didUseRefinement }
        case .refinedOnly:
            return records.filter { $0.didUseRefinement }
        }
    }

    func recordsGroupedByDate(filter: HistoryFilter) -> [(String, [TranscriptionRecord])] {
        let filtered = filteredRecords(filter: filter)

        let grouped = Dictionary(grouping: filtered) { record in
            DateFormatting.dateString(from: record.date)
        }

        let calendar = Calendar.current
        return grouped.sorted { a, b in
            guard let dateA = a.value.first?.date, let dateB = b.value.first?.date else { return false }
            return calendar.compare(dateA, to: dateB, toGranularity: .day) == .orderedDescending
        }
    }

    var databaseFileSize: Int64 {
        database.databaseFileSize()
    }

    // MARK: - Persistence (Encrypted)

    private func loadRecords() {
        do {
            let encrypted = try database.fetchAll()
            records = encrypted.compactMap { decryptRecord($0) }
        } catch {
            print("[History] Failed to load records: \(error)")
        }
    }

    private func saveRecord(_ record: TranscriptionRecord) {
        guard let encrypted = encryptRecord(record) else { return }
        do {
            try database.insert(encrypted)
        } catch {
            print("[History] Failed to save record: \(error)")
        }
    }

    private func pruneExpired() {
        guard let interval = retention.timeInterval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let before = records.count
        records.removeAll { $0.date < cutoff }
        if records.count != before {
            _ = try? database.deleteBefore(date: cutoff.timeIntervalSince1970)
        }
    }

    // MARK: - Encrypt / Decrypt

    private func encryptRecord(_ r: TranscriptionRecord) -> EncryptedRecord? {
        do {
            let encRaw = try encryption.encrypt(string: r.rawText)
            let encRefined = try encryption.encrypt(string: r.refinedText)
            let encAudio = try r.audioData.map { try encryption.encrypt($0) }

            return EncryptedRecord(
                id: r.id.uuidString,
                date: r.date.timeIntervalSince1970,
                encryptedRawText: encRaw,
                encryptedRefinedText: encRefined,
                encryptedAudioData: encAudio,
                didUseRefinement: r.didUseRefinement,
                transcriptionModel: r.transcriptionMeta?.model,
                transcriptionTime: r.transcriptionMeta?.responseTime,
                refinementModel: r.refinementMeta?.model,
                refinementTime: r.refinementMeta?.responseTime,
                tokenPrompt: r.transcriptionMeta?.tokenUsage?.promptTokens
                    ?? r.refinementMeta?.tokenUsage?.promptTokens,
                tokenCompletion: r.transcriptionMeta?.tokenUsage?.completionTokens
                    ?? r.refinementMeta?.tokenUsage?.completionTokens,
                tokenTotal: r.transcriptionMeta?.tokenUsage?.totalTokens
                    ?? r.refinementMeta?.tokenUsage?.totalTokens,
                transcriptionCost: r.transcriptionMeta?.cost,
                refinementCost: r.refinementMeta?.cost
            )
        } catch {
            print("[History] Encryption failed: \(error)")
            return nil
        }
    }

    private func decryptRecord(_ e: EncryptedRecord) -> TranscriptionRecord? {
        do {
            let raw = try encryption.decryptString(from: e.encryptedRawText)
            let refined = try encryption.decryptString(from: e.encryptedRefinedText)
            let audio = try e.encryptedAudioData.map { try encryption.decrypt($0) }

            let sttMeta: APICallMetadata? = {
                guard let model = e.transcriptionModel else { return nil }
                let usage: TokenUsage? = nil
                return APICallMetadata(
                    model: model,
                    responseTime: e.transcriptionTime ?? 0,
                    tokenUsage: usage,
                    cost: e.transcriptionCost
                )
            }()

            let llmMeta: APICallMetadata? = {
                guard let model = e.refinementModel else { return nil }
                let usage: TokenUsage? = {
                    guard let p = e.tokenPrompt, let c = e.tokenCompletion, let t = e.tokenTotal else {
                        return nil
                    }
                    return TokenUsage(promptTokens: p, completionTokens: c, totalTokens: t)
                }()
                return APICallMetadata(
                    model: model,
                    responseTime: e.refinementTime ?? 0,
                    tokenUsage: usage,
                    cost: e.refinementCost
                )
            }()

            return TranscriptionRecord(
                id: UUID(uuidString: e.id) ?? UUID(),
                date: Date(timeIntervalSince1970: e.date),
                rawText: raw,
                refinedText: refined,
                didUseRefinement: e.didUseRefinement,
                transcriptionMeta: sttMeta,
                refinementMeta: llmMeta,
                audioData: audio
            )
        } catch {
            print("[History] Decryption failed for \(e.id): \(error)")
            return nil
        }
    }

    // MARK: - JSON Migration

    private func migrateFromJSON() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let jsonURL = appSupport
            .appendingPathComponent("VoiceToText", isDirectory: true)
            .appendingPathComponent("history.json")

        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        do {
            let data = try Data(contentsOf: jsonURL)
            let legacy = try JSONDecoder().decode([LegacyRecord].self, from: data)

            for old in legacy {
                let record = TranscriptionRecord(
                    id: old.id,
                    date: old.date,
                    rawText: old.rawText,
                    refinedText: old.refinedText,
                    didUseRefinement: old.didUseRefinement,
                    transcriptionMeta: old.transcriptionMeta,
                    refinementMeta: old.refinementMeta
                )
                if let encrypted = encryptRecord(record) {
                    try database.insert(encrypted)
                }
            }

            let backupURL = jsonURL.deletingPathExtension().appendingPathExtension("json.bak")
            try FileManager.default.moveItem(at: jsonURL, to: backupURL)
            print("[History] Migrated \(legacy.count) records from JSON to encrypted database")
        } catch {
            print("[History] JSON migration failed: \(error)")
        }
    }
}
