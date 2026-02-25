import Foundation

@MainActor
final class HotwordsManager: ObservableObject {

    @Published private(set) var hotwords: [String] = []

    private let storageKey = "hotwords"

    init() {
        hotwords = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    /// Returns false if the word already exists, is empty, or the limit is reached.
    @discardableResult
    func add(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !hotwords.contains(trimmed),
              hotwords.count < Limits.maxHotwords else { return false }
        hotwords.append(trimmed)
        save()
        return true
    }

    func remove(_ word: String) {
        hotwords.removeAll { $0 == word }
        save()
    }

    func remove(at offsets: IndexSet) {
        hotwords.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        hotwords.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(hotwords, forKey: storageKey)
    }
}
