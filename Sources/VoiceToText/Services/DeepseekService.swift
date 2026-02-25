import Foundation

struct RefinementOutput {
    let text: String
    let model: String
    let tokenUsage: TokenUsage?
    let responseTime: TimeInterval
}

final class DeepseekService: RefinementServiceProtocol {

    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let model = "deepseek-chat"
    private let timeoutInterval: TimeInterval = 60

    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    /// 使用 Deepseek LLM 对原始转录文本进行润色
    /// - Parameters:
    ///   - text: STT 返回的原始文本
    ///   - systemPrompt: 用户自定义的润色 Prompt
    /// - Returns: 润色结果（含模型名、token 用量和响应时间）
    func refine(text: String, systemPrompt: String) async throws -> RefinementOutput {
        let requestBody = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ]
        )

        let jsonData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = timeoutInterval

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await urlSession.data(for: request)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw DeepseekError.requestFailed(statusCode: statusCode, message: responseBody)
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw DeepseekError.emptyResponse
        }

        let tokenUsage: TokenUsage? = result.usage.map {
            TokenUsage(
                promptTokens: $0.prompt_tokens,
                completionTokens: $0.completion_tokens,
                totalTokens: $0.total_tokens
            )
        }

        return RefinementOutput(
            text: content,
            model: result.model ?? model,
            tokenUsage: tokenUsage,
            responseTime: elapsed
        )
    }
}

// MARK: - Request / Response Models

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
    let model: String?

    struct Choice: Decodable {
        let message: MessageContent
    }

    struct MessageContent: Decodable {
        let content: String?
    }

    struct Usage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

// MARK: - Errors

enum DeepseekError: LocalizedError {
    case requestFailed(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let message):
            return "Deepseek API error (\(code)): \(message)"
        case .emptyResponse:
            return "Deepseek API returned an empty response"
        }
    }
}
