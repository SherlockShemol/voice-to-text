import XCTest
@testable import VoiceToText

final class HistoryRetentionTests: XCTestCase {

    // MARK: - HistoryRetention timeInterval

    func testForeverReturnsNil() {
        XCTAssertNil(HistoryRetention.forever.timeInterval)
    }

    func testOneMonthReturns30Days() {
        let expected: TimeInterval = 30 * 24 * 3600
        XCTAssertEqual(HistoryRetention.oneMonth.timeInterval, expected)
    }

    func testOneWeekReturns7Days() {
        let expected: TimeInterval = 7 * 24 * 3600
        XCTAssertEqual(HistoryRetention.oneWeek.timeInterval, expected)
    }

    func testOneDayReturns24Hours() {
        let expected: TimeInterval = 24 * 3600
        XCTAssertEqual(HistoryRetention.oneDay.timeInterval, expected)
    }

    // MARK: - HistoryRetention rawValue (Chinese labels)

    func testForeverRawValue() {
        XCTAssertEqual(HistoryRetention.forever.rawValue, "永远")
    }

    func testOneMonthRawValue() {
        XCTAssertEqual(HistoryRetention.oneMonth.rawValue, "一个月")
    }

    func testOneWeekRawValue() {
        XCTAssertEqual(HistoryRetention.oneWeek.rawValue, "一周")
    }

    func testOneDayRawValue() {
        XCTAssertEqual(HistoryRetention.oneDay.rawValue, "一天")
    }

    // MARK: - HistoryRetention CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(HistoryRetention.allCases.count, 4)
    }

    // MARK: - HistoryRetention Codable

    func testCodableRoundTrip() throws {
        for retention in HistoryRetention.allCases {
            let data = try JSONEncoder().encode(retention)
            let decoded = try JSONDecoder().decode(HistoryRetention.self, from: data)
            XCTAssertEqual(decoded, retention)
        }
    }

    // MARK: - HistoryFilter rawValue

    func testFilterAllRawValue() {
        XCTAssertEqual(HistoryFilter.all.rawValue, "全部")
    }

    func testFilterTranscribedOnlyRawValue() {
        XCTAssertEqual(HistoryFilter.transcribedOnly.rawValue, "仅转录")
    }

    func testFilterRefinedOnlyRawValue() {
        XCTAssertEqual(HistoryFilter.refinedOnly.rawValue, "仅润色")
    }

    func testFilterAllCasesCount() {
        XCTAssertEqual(HistoryFilter.allCases.count, 3)
    }
}
