import XCTest
@testable import VoiceToText

private final class MockURLProtocol: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class DeepseekServiceTests: XCTestCase {

    private var sut: DeepseekService!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sut = DeepseekService(apiKey: "test-deepseek-key", urlSession: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        sut = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Success

    func testRefineSuccessfulResponse() async throws {
        let json = """
        {
            "choices": [
                {
                    "message": { "content": "润色后的文本。" }
                }
            ],
            "usage": {
                "prompt_tokens": 120,
                "completion_tokens": 80,
                "total_tokens": 200
            },
            "model": "deepseek-chat"
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let output = try await sut.refine(text: "原始文本", systemPrompt: "请润色")

        XCTAssertEqual(output.text, "润色后的文本。")
        XCTAssertEqual(output.model, "deepseek-chat")
        XCTAssertEqual(output.tokenUsage?.promptTokens, 120)
        XCTAssertEqual(output.tokenUsage?.completionTokens, 80)
        XCTAssertEqual(output.tokenUsage?.totalTokens, 200)
        XCTAssertGreaterThanOrEqual(output.responseTime, 0)
    }

    func testRefineUsesDefaultModelWhenResponseModelIsNil() async throws {
        let json = """
        {
            "choices": [{"message": {"content": "text"}}],
            "usage": null
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let output = try await sut.refine(text: "test", systemPrompt: "prompt")
        XCTAssertEqual(output.model, "deepseek-chat")
    }

    func testRefineWithoutUsage() async throws {
        let json = """
        {
            "choices": [{"message": {"content": "result"}}]
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let output = try await sut.refine(text: "test", systemPrompt: "prompt")
        XCTAssertNil(output.tokenUsage)
    }

    // MARK: - Empty response

    func testRefineEmptyResponse() async {
        let json = """
        {
            "choices": [{"message": {"content": null}}],
            "model": "deepseek-chat"
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await sut.refine(text: "test", systemPrompt: "prompt")
            XCTFail("Expected DeepseekError.emptyResponse")
        } catch let error as DeepseekError {
            XCTAssertEqual(error.errorDescription, "Deepseek API returned an empty response")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefineEmptyChoices() async {
        let json = """
        {
            "choices": [],
            "model": "deepseek-chat"
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await sut.refine(text: "test", systemPrompt: "prompt")
            XCTFail("Expected DeepseekError.emptyResponse")
        } catch is DeepseekError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - HTTP Errors

    func testRefineHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Rate limited".utf8))
        }

        do {
            _ = try await sut.refine(text: "test", systemPrompt: "prompt")
            XCTFail("Expected DeepseekError")
        } catch let error as DeepseekError {
            let desc = error.errorDescription ?? ""
            XCTAssertTrue(desc.contains("429"))
            XCTAssertTrue(desc.contains("Rate limited"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefineUnauthorized() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Invalid API key".utf8))
        }

        do {
            _ = try await sut.refine(text: "test", systemPrompt: "prompt")
            XCTFail("Expected error")
        } catch is DeepseekError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Invalid JSON

    func testRefineInvalidJSON() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{broken".utf8))
        }

        do {
            _ = try await sut.refine(text: "test", systemPrompt: "prompt")
            XCTFail("Expected decoding error")
        } catch is DecodingError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Request format

    func testRequestContainsBearerToken() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {"choices": [{"message": {"content": "ok"}}]}
        """
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        _ = try await sut.refine(text: "test", systemPrompt: "prompt")

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-deepseek-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    func testRequestBodyContainsMessages() async throws {
        var capturedBody: Data?
        let json = """
        {"choices": [{"message": {"content": "ok"}}]}
        """
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody {
                capturedBody = body
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buf, maxLength: 4096)
                    if read <= 0 { break }
                    data.append(buf, count: read)
                }
                stream.close()
                capturedBody = data
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        _ = try await sut.refine(text: "用户输入", systemPrompt: "系统指令")

        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("用户输入"))
        XCTAssertTrue(bodyString.contains("系统指令"))
        XCTAssertTrue(bodyString.contains("deepseek-chat"))
    }

    // MARK: - Error descriptions

    func testDeepseekErrorRequestFailedDescription() {
        let error = DeepseekError.requestFailed(statusCode: 500, message: "Server Error")
        XCTAssertEqual(error.errorDescription, "Deepseek API error (500): Server Error")
    }

    func testDeepseekErrorEmptyResponseDescription() {
        let error = DeepseekError.emptyResponse
        XCTAssertEqual(error.errorDescription, "Deepseek API returned an empty response")
    }
}
