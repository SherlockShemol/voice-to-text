import XCTest
@testable import VoiceToText

@MainActor
final class HotwordsManagerTests: XCTestCase {

    private var manager: HotwordsManager!
    private let storageKey = "hotwords"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
        manager = HotwordsManager()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    // MARK: - Add

    func testAddHotword() {
        let result = manager.add("Swift")
        XCTAssertTrue(result)
        XCTAssertEqual(manager.hotwords, ["Swift"])
    }

    func testAddDuplicateReturnsFalse() {
        manager.add("Swift")
        let result = manager.add("Swift")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.hotwords.count, 1)
    }

    func testAddEmptyStringReturnsFalse() {
        let result = manager.add("   ")
        XCTAssertFalse(result)
        XCTAssertTrue(manager.hotwords.isEmpty)
    }

    func testAddTrimsWhitespace() {
        manager.add("  Hello  ")
        XCTAssertEqual(manager.hotwords, ["Hello"])
    }

    func testAddRespectsLimit() {
        for i in 0..<Limits.maxHotwords {
            manager.add("word\(i)")
        }
        let result = manager.add("overflow")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.hotwords.count, Limits.maxHotwords)
    }

    // MARK: - Remove

    func testRemoveHotword() {
        manager.add("Swift")
        manager.add("Xcode")
        manager.remove("Swift")
        XCTAssertEqual(manager.hotwords, ["Xcode"])
    }

    func testRemoveNonexistentWord() {
        manager.add("Swift")
        manager.remove("NotThere")
        XCTAssertEqual(manager.hotwords, ["Swift"])
    }

    func testRemoveAtOffsets() {
        manager.add("A")
        manager.add("B")
        manager.add("C")
        manager.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(manager.hotwords, ["A", "C"])
    }

    // MARK: - Clear

    func testClearAll() {
        manager.add("A")
        manager.add("B")
        manager.clearAll()
        XCTAssertTrue(manager.hotwords.isEmpty)
    }

    // MARK: - Persistence

    func testPersistsToUserDefaults() {
        manager.add("Persisted")
        let saved = UserDefaults.standard.stringArray(forKey: storageKey)
        XCTAssertEqual(saved, ["Persisted"])
    }

    func testLoadsFromUserDefaults() {
        UserDefaults.standard.set(["Loaded"], forKey: storageKey)
        let fresh = HotwordsManager()
        XCTAssertEqual(fresh.hotwords, ["Loaded"])
    }
}
