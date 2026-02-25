import XCTest
@testable import VoiceToText

// MARK: - Mocks

private final class MockTranscriptionService: TranscriptionServiceProtocol {
    var result: TranscriptionOutput?
    var error: Error?
    var transcribeCalled = false
    var receivedFileURL: URL?
    var receivedHotwords: [String]?

    func transcribe(fileURL: URL, hotwords: [String]?) async throws -> TranscriptionOutput {
        transcribeCalled = true
        receivedFileURL = fileURL
        receivedHotwords = hotwords
        if let error { throw error }
        return result!
    }
}

private final class MockRefinementService: RefinementServiceProtocol {
    var result: RefinementOutput?
    var error: Error?
    var refineCalled = false
    var receivedText: String?
    var receivedPrompt: String?

    func refine(text: String, systemPrompt: String) async throws -> RefinementOutput {
        refineCalled = true
        receivedText = text
        receivedPrompt = systemPrompt
        if let error { throw error }
        return result!
    }
}

private enum TestError: Error {
    case refinementFailed
    case transcriptionFailed
}

// MARK: - Tests

final class SpeechProcessorTests: XCTestCase {

    private var mockSTT: MockTranscriptionService!
    private var mockLLM: MockRefinementService!
    private let dummyURL = URL(fileURLWithPath: "/tmp/test.wav")

    override func setUp() {
        super.setUp()
        mockSTT = MockTranscriptionService()
        mockLLM = MockRefinementService()

        mockSTT.result = TranscriptionOutput(
            text: "你好世界",
            model: "glm-asr-2512",
            responseTime: 1.5,
            audioDuration: 3.0
        )

        mockLLM.result = RefinementOutput(
            text: "你好，世界。",
            model: "deepseek-chat",
            tokenUsage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            responseTime: 0.8
        )
    }

    // MARK: - Full pipeline (transcription + refinement)

    func testFullPipelineSuccess() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "请润色"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertTrue(mockSTT.transcribeCalled)
        XCTAssertTrue(mockLLM.refineCalled)
        XCTAssertEqual(result.rawText, "你好世界")
        XCTAssertEqual(result.refinedText, "你好，世界。")
        XCTAssertFalse(result.didFallback)
    }

    func testFullPipelinePassesCorrectPromptToRefinement() async throws {
        let prompt = "自定义润色指令"
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: prompt
        )

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertEqual(mockLLM.receivedPrompt, prompt)
        XCTAssertEqual(mockLLM.receivedText, "你好世界")
    }

    func testFullPipelineTranscriptionMetadata() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertNotNil(result.transcriptionMeta)
        XCTAssertEqual(result.transcriptionMeta?.model, "glm-asr-2512")
        XCTAssertEqual(result.transcriptionMeta?.responseTime, 1.5)
        let expectedCost = Pricing.sttCost(audioDurationSeconds: 3.0)
        XCTAssertEqual(result.transcriptionMeta?.cost, expectedCost)
    }

    func testFullPipelineRefinementMetadata() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertNotNil(result.refinementMeta)
        XCTAssertEqual(result.refinementMeta?.model, "deepseek-chat")
        XCTAssertEqual(result.refinementMeta?.responseTime, 0.8)
        XCTAssertEqual(result.refinementMeta?.tokenUsage?.promptTokens, 100)
        XCTAssertEqual(result.refinementMeta?.tokenUsage?.completionTokens, 50)
        let expectedCost = Pricing.llmCost(promptTokens: 100, completionTokens: 50)
        XCTAssertEqual(result.refinementMeta!.cost!, expectedCost, accuracy: 1e-10)
    }

    // MARK: - Skip refinement

    func testSkipsRefinementWhenServiceIsNil() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: nil,
            polishPrompt: "prompt"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertTrue(mockSTT.transcribeCalled)
        XCTAssertFalse(mockLLM.refineCalled)
        XCTAssertEqual(result.rawText, "你好世界")
        XCTAssertEqual(result.refinedText, "你好世界")
        XCTAssertTrue(result.didFallback)
        XCTAssertNil(result.refinementMeta)
    }

    func testSkipsRefinementWhenPromptIsEmpty() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: ""
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertTrue(mockSTT.transcribeCalled)
        XCTAssertFalse(mockLLM.refineCalled)
        XCTAssertEqual(result.refinedText, "你好世界")
        XCTAssertTrue(result.didFallback)
    }

    // MARK: - Refinement fallback

    func testFallbackWhenRefinementFails() async throws {
        mockLLM.error = TestError.refinementFailed

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertTrue(mockLLM.refineCalled)
        XCTAssertEqual(result.rawText, "你好世界")
        XCTAssertEqual(result.refinedText, "你好世界")
        XCTAssertTrue(result.didFallback)
        XCTAssertNil(result.refinementMeta)
        XCTAssertNotNil(result.transcriptionMeta)
    }

    // MARK: - Transcription failure propagates

    func testTranscriptionErrorPropagates() async {
        mockSTT.error = TestError.transcriptionFailed

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )

        do {
            _ = try await processor.process(audioFileURL: dummyURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - Stage change callbacks

    func testStageChangeCallbackOrder() async throws {
        var stages: [ProcessingStage] = []

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )
        processor.onStageChange = { stage in
            stages.append(stage)
        }

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertEqual(stages, [.transcribing, .refining])
    }

    func testStageChangeCallbackOnlyTranscribingWhenNoRefinement() async throws {
        var stages: [ProcessingStage] = []

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: nil,
            polishPrompt: "prompt"
        )
        processor.onStageChange = { stage in
            stages.append(stage)
        }

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertEqual(stages, [.transcribing])
    }

    func testStageChangeCallbackBothStagesEvenWhenRefinementFails() async throws {
        var stages: [ProcessingStage] = []
        mockLLM.error = TestError.refinementFailed

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )
        processor.onStageChange = { stage in
            stages.append(stage)
        }

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertEqual(stages, [.transcribing, .refining])
    }

    // MARK: - File URL forwarding

    func testFileURLIsForwardedToTranscriptionService() async throws {
        let url = URL(fileURLWithPath: "/tmp/custom-recording.wav")
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: nil,
            polishPrompt: ""
        )

        _ = try await processor.process(audioFileURL: url)

        XCTAssertEqual(mockSTT.receivedFileURL, url)
    }

    // MARK: - Refinement with nil token usage

    func testRefinementMetadataWithNilTokenUsage() async throws {
        mockLLM.result = RefinementOutput(
            text: "refined",
            model: "deepseek-chat",
            tokenUsage: nil,
            responseTime: 0.5
        )

        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: mockLLM,
            polishPrompt: "prompt"
        )

        let result = try await processor.process(audioFileURL: dummyURL)

        XCTAssertNotNil(result.refinementMeta)
        XCTAssertNil(result.refinementMeta?.tokenUsage)
        XCTAssertNil(result.refinementMeta?.cost)
    }

    // MARK: - Hotwords

    func testHotwordsAreForwardedToTranscriptionService() async throws {
        let words = ["SDK", "Gemini", "Kagi"]
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: nil,
            polishPrompt: "",
            hotwords: words
        )

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertEqual(mockSTT.receivedHotwords, words)
    }

    func testEmptyHotwordsPassesNilToTranscriptionService() async throws {
        let processor = SpeechProcessor(
            transcriptionService: mockSTT,
            refinementService: nil,
            polishPrompt: ""
        )

        _ = try await processor.process(audioFileURL: dummyURL)

        XCTAssertNil(mockSTT.receivedHotwords)
    }
}
