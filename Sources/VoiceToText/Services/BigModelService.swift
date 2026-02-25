import Foundation
import AVFoundation

struct TranscriptionOutput {
    let text: String
    let model: String
    let responseTime: TimeInterval
    let audioDuration: TimeInterval
}

private struct TranscriptionResponse: Codable {
    let id: String
    let created: Int
    let requestId: String?
    let model: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case id, created, model, text
        case requestId = "request_id"
    }
}

final class BigModelService: TranscriptionServiceProtocol {

    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions")!
    private let model = "glm-asr-2512"

    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    /// 将音频文件转录为文本
    /// - Parameters:
    ///   - fileURL: 本地音频文件路径（支持 .wav / .mp3，≤ 25MB，≤ 30s）
    ///   - hotwords: 热词表，提升特定词汇识别率（可选，最多 100 个）
    /// - Returns: 转录结果（含模型名和响应时间）
    func transcribe(fileURL: URL, hotwords: [String]? = nil) async throws -> TranscriptionOutput {
        let audioDuration = Self.audioDuration(of: fileURL)
        let fileData = try Data(contentsOf: fileURL)
        let boundary = UUID().uuidString

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        appendFormField(&body, boundary: boundary, name: "model", value: model)
        appendFormField(&body, boundary: boundary, name: "stream", value: "false")

        if let hotwords, !hotwords.isEmpty {
            for word in hotwords {
                appendFormField(&body, boundary: boundary, name: "hotwords", value: word)
            }
        }

        let filename = fileURL.lastPathComponent
        let mimeType = filename.hasSuffix(".wav") ? "audio/wav" : "audio/mpeg"
        appendFileField(&body, boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: fileData)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await urlSession.data(for: request)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw BigModelError.requestFailed(statusCode: statusCode, message: responseBody)
        }

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return TranscriptionOutput(
            text: result.text,
            model: result.model ?? model,
            responseTime: elapsed,
            audioDuration: audioDuration
        )
    }

    private static func audioDuration(of url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    // MARK: - Multipart Helpers

    private func appendFormField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileField(_ body: inout Data, boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }
}

enum BigModelError: LocalizedError {
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let message):
            return "BigModel API error (\(code)): \(message)"
        }
    }
}
