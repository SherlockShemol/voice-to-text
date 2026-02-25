import XCTest
@testable import VoiceToText

final class TranscriptionRecordTests: XCTestCase {

    // MARK: - displayText

    func testDisplayTextReturnsRefinedTextWhenRefinementUsed() {
        let record = TranscriptionRecord(
            rawText: "原始文本",
            refinedText: "润色后的文本",
            didUseRefinement: true
        )
        XCTAssertEqual(record.displayText, "润色后的文本")
    }

    func testDisplayTextReturnsRawTextWhenRefinementNotUsed() {
        let record = TranscriptionRecord(
            rawText: "原始文本",
            refinedText: "原始文本",
            didUseRefinement: false
        )
        XCTAssertEqual(record.displayText, "原始文本")
    }

    func testDisplayTextReturnsRawTextEvenIfRefinedTextDiffers() {
        let record = TranscriptionRecord(
            rawText: "raw",
            refinedText: "refined",
            didUseRefinement: false
        )
        XCTAssertEqual(record.displayText, "raw")
    }

    // MARK: - totalCost

    func testTotalCostWithBothSTTAndLLM() {
        let sttMeta = APICallMetadata(model: "glm", responseTime: 1.0, tokenUsage: nil, cost: 0.003)
        let llmMeta = APICallMetadata(model: "deepseek", responseTime: 0.5, tokenUsage: nil, cost: 0.001)
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: true,
            transcriptionMeta: sttMeta,
            refinementMeta: llmMeta
        )
        XCTAssertEqual(record.totalCost!, 0.004, accuracy: 1e-10)
    }

    func testTotalCostWithOnlySTT() {
        let sttMeta = APICallMetadata(model: "glm", responseTime: 1.0, tokenUsage: nil, cost: 0.003)
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: false,
            transcriptionMeta: sttMeta,
            refinementMeta: nil
        )
        XCTAssertEqual(record.totalCost!, 0.003, accuracy: 1e-10)
    }

    func testTotalCostWithOnlyLLM() {
        let llmMeta = APICallMetadata(model: "deepseek", responseTime: 0.5, tokenUsage: nil, cost: 0.002)
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: true,
            transcriptionMeta: nil,
            refinementMeta: llmMeta
        )
        XCTAssertEqual(record.totalCost!, 0.002, accuracy: 1e-10)
    }

    func testTotalCostNilWhenNoCosts() {
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: false
        )
        XCTAssertNil(record.totalCost)
    }

    func testTotalCostNilWhenMetaHasNilCosts() {
        let sttMeta = APICallMetadata(model: "glm", responseTime: 1.0, tokenUsage: nil, cost: nil)
        let llmMeta = APICallMetadata(model: "deepseek", responseTime: 0.5, tokenUsage: nil, cost: nil)
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: true,
            transcriptionMeta: sttMeta,
            refinementMeta: llmMeta
        )
        XCTAssertNil(record.totalCost)
    }

    func testTotalCostWhenOneMetaHasNilCostAndOtherHasValue() {
        let sttMeta = APICallMetadata(model: "glm", responseTime: 1.0, tokenUsage: nil, cost: 0.005)
        let llmMeta = APICallMetadata(model: "deepseek", responseTime: 0.5, tokenUsage: nil, cost: nil)
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: true,
            transcriptionMeta: sttMeta,
            refinementMeta: llmMeta
        )
        XCTAssertEqual(record.totalCost!, 0.005, accuracy: 1e-10)
    }

    // MARK: - hasAudio

    func testHasAudioTrueWhenAudioDataPresent() {
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: false,
            audioData: Data([0x00, 0x01, 0x02])
        )
        XCTAssertTrue(record.hasAudio)
    }

    func testHasAudioFalseWhenAudioDataNil() {
        let record = TranscriptionRecord(
            rawText: "test",
            refinedText: "test",
            didUseRefinement: false,
            audioData: nil
        )
        XCTAssertFalse(record.hasAudio)
    }

    // MARK: - Default values

    func testDefaultIdIsGenerated() {
        let r1 = TranscriptionRecord(rawText: "a", refinedText: "b", didUseRefinement: false)
        let r2 = TranscriptionRecord(rawText: "a", refinedText: "b", didUseRefinement: false)
        XCTAssertNotEqual(r1.id, r2.id)
    }

    func testCustomIdIsPreserved() {
        let id = UUID()
        let record = TranscriptionRecord(
            id: id,
            rawText: "a",
            refinedText: "b",
            didUseRefinement: false
        )
        XCTAssertEqual(record.id, id)
    }

    func testCustomDateIsPreserved() {
        let date = Date(timeIntervalSince1970: 1000)
        let record = TranscriptionRecord(
            date: date,
            rawText: "a",
            refinedText: "b",
            didUseRefinement: false
        )
        XCTAssertEqual(record.date, date)
    }
}
