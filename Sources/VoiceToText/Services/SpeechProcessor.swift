import Foundation

enum ProcessingStage {
    case transcribing
    case refining
}

struct ProcessingResult {
    let rawText: String
    let refinedText: String
    /// 润色是否因错误而降级为原始文本
    let didFallback: Bool
    let transcriptionMeta: APICallMetadata?
    let refinementMeta: APICallMetadata?
}

protocol TranscriptionServiceProtocol {
    func transcribe(fileURL: URL, hotwords: [String]?) async throws -> TranscriptionOutput
}

protocol RefinementServiceProtocol {
    func refine(text: String, systemPrompt: String) async throws -> RefinementOutput
}

final class SpeechProcessor {

    private let bigModelService: any TranscriptionServiceProtocol
    private let deepseekService: (any RefinementServiceProtocol)?
    private let polishPrompt: String
    private let hotwords: [String]

    var onStageChange: ((ProcessingStage) -> Void)?

    /// - Parameters:
    ///   - bigModelAPIKey: BigModel STT API 密钥
    ///   - deepseekAPIKey: Deepseek 润色 API 密钥（为空则跳过润色）
    ///   - polishPrompt: 用户自定义润色 Prompt（为空则跳过润色）
    ///   - hotwords: 热词表，提升特定词汇识别率（最多 100 个）
    init(bigModelAPIKey: String, deepseekAPIKey: String, polishPrompt: String, hotwords: [String] = []) {
        self.bigModelService = BigModelService(apiKey: bigModelAPIKey)
        self.deepseekService = deepseekAPIKey.isEmpty ? nil : DeepseekService(apiKey: deepseekAPIKey)
        self.polishPrompt = polishPrompt
        self.hotwords = hotwords
    }

    init(
        transcriptionService: any TranscriptionServiceProtocol,
        refinementService: (any RefinementServiceProtocol)?,
        polishPrompt: String,
        hotwords: [String] = []
    ) {
        self.bigModelService = transcriptionService
        self.deepseekService = refinementService
        self.polishPrompt = polishPrompt
        self.hotwords = hotwords
    }

    /// 完整处理流水线：音频 -> 转录 -> 润色
    func process(audioFileURL: URL) async throws -> ProcessingResult {
        onStageChange?(.transcribing)
        let sttOutput = try await bigModelService.transcribe(fileURL: audioFileURL, hotwords: hotwords.isEmpty ? nil : hotwords)
        let sttCost = Pricing.sttCost(audioDurationSeconds: sttOutput.audioDuration)
        let sttMeta = APICallMetadata(
            model: sttOutput.model,
            responseTime: sttOutput.responseTime,
            tokenUsage: nil,
            cost: sttCost
        )

        guard let deepseekService, !polishPrompt.isEmpty else {
            return ProcessingResult(
                rawText: sttOutput.text,
                refinedText: sttOutput.text,
                didFallback: true,
                transcriptionMeta: sttMeta,
                refinementMeta: nil
            )
        }

        onStageChange?(.refining)
        do {
            let llmOutput = try await deepseekService.refine(text: sttOutput.text, systemPrompt: polishPrompt)
            let llmCost = llmOutput.tokenUsage.map {
                Pricing.llmCost(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens)
            }
            let llmMeta = APICallMetadata(
                model: llmOutput.model,
                responseTime: llmOutput.responseTime,
                tokenUsage: llmOutput.tokenUsage,
                cost: llmCost
            )
            return ProcessingResult(
                rawText: sttOutput.text,
                refinedText: llmOutput.text,
                didFallback: false,
                transcriptionMeta: sttMeta,
                refinementMeta: llmMeta
            )
        } catch {
            print("[SpeechProcessor] Refinement failed, falling back to raw text: \(error)")
            return ProcessingResult(
                rawText: sttOutput.text,
                refinedText: sttOutput.text,
                didFallback: true,
                transcriptionMeta: sttMeta,
                refinementMeta: nil
            )
        }
    }
}
