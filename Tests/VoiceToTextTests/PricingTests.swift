import XCTest
@testable import VoiceToText

final class PricingTests: XCTestCase {

    // MARK: - STT Cost

    func testSTTCostZeroSeconds() {
        XCTAssertEqual(Pricing.sttCost(audioDurationSeconds: 0), 0, accuracy: 1e-10)
    }

    func testSTTCostOneMinute() {
        // ¥0.06/分钟 × 1 分钟 = ¥0.06
        XCTAssertEqual(Pricing.sttCost(audioDurationSeconds: 60), 0.06, accuracy: 1e-10)
    }

    func testSTTCostThirtySeconds() {
        // ¥0.06/分钟 × 0.5 分钟 = ¥0.03
        XCTAssertEqual(Pricing.sttCost(audioDurationSeconds: 30), 0.03, accuracy: 1e-10)
    }

    func testSTTCostTenMinutes() {
        // ¥0.06/分钟 × 10 分钟 = ¥0.60
        XCTAssertEqual(Pricing.sttCost(audioDurationSeconds: 600), 0.60, accuracy: 1e-10)
    }

    func testSTTCostFractionalSeconds() {
        // 45 秒 = 0.75 分钟 → ¥0.06 × 0.75 = ¥0.045
        XCTAssertEqual(Pricing.sttCost(audioDurationSeconds: 45), 0.045, accuracy: 1e-10)
    }

    // MARK: - LLM Cost

    func testLLMCostZeroTokens() {
        XCTAssertEqual(Pricing.llmCost(promptTokens: 0, completionTokens: 0), 0, accuracy: 1e-10)
    }

    func testLLMCostOnlyPromptTokens() {
        // 1,000,000 输入 tokens × ¥2/百万 = ¥2.0
        XCTAssertEqual(Pricing.llmCost(promptTokens: 1_000_000, completionTokens: 0), 2.0, accuracy: 1e-10)
    }

    func testLLMCostOnlyCompletionTokens() {
        // 1,000,000 输出 tokens × ¥3/百万 = ¥3.0
        XCTAssertEqual(Pricing.llmCost(promptTokens: 0, completionTokens: 1_000_000), 3.0, accuracy: 1e-10)
    }

    func testLLMCostMixed() {
        // 100 输入 × ¥2/百万 + 50 输出 × ¥3/百万
        // = 0.0002 + 0.00015 = 0.00035
        let cost = Pricing.llmCost(promptTokens: 100, completionTokens: 50)
        XCTAssertEqual(cost, 0.00035, accuracy: 1e-10)
    }

    func testLLMCostTypicalUsage() {
        // 120 输入 + 80 输出
        // = 120 × 2/1M + 80 × 3/1M = 0.00024 + 0.00024 = 0.00048
        let cost = Pricing.llmCost(promptTokens: 120, completionTokens: 80)
        XCTAssertEqual(cost, 0.00048, accuracy: 1e-10)
    }

    // MARK: - Pricing Constants

    func testSTTPricePerMinute() {
        XCTAssertEqual(Pricing.sttPricePerMinute, 0.06)
    }

    func testLLMInputPricePerMillion() {
        XCTAssertEqual(Pricing.llmInputPricePerMillion, 2.0)
    }

    func testLLMOutputPricePerMillion() {
        XCTAssertEqual(Pricing.llmOutputPricePerMillion, 3.0)
    }
}
