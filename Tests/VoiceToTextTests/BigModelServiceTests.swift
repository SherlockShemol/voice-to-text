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

final class BigModelServiceTests: XCTestCase {

    private var sut: BigModelService!
    private var session: URLSession!
    private var tempAudioURL: URL!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sut = BigModelService(apiKey: "test-api-key", urlSession: session)

        tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try? Data([0x00, 0x01]).write(to: tempAudioURL)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        try? FileManager.default.removeItem(at: tempAudioURL)
        sut = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Success

    func testTranscribeSuccessfulResponse() async throws {
        let json = """
        {
            "id": "req-123",
            "created": 1700000000,
            "model": "glm-asr-2512",
            "text": "你好世界"
        }
        """
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains("test-api-key") ?? false)
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(contentType.starts(with: "multipart/form-data"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let output = try await sut.transcribe(fileURL: tempAudioURL)

        XCTAssertEqual(output.text, "你好世界")
        XCTAssertEqual(output.model, "glm-asr-2512")
        XCTAssertGreaterThanOrEqual(output.responseTime, 0)
    }

    func testTranscribeUsesDefaultModelWhenResponseModelIsNil() async throws {
        let json = """
        {
            "id": "req-456",
            "created": 1700000000,
            "text": "test"
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

        let output = try await sut.transcribe(fileURL: tempAudioURL)
        XCTAssertEqual(output.model, "glm-asr-2512")
    }

    // MARK: - HTTP Errors

    func testTranscribeHTTPError() async {
        let errorBody = "Unauthorized"
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(errorBody.utf8))
        }

        do {
            _ = try await sut.transcribe(fileURL: tempAudioURL)
            XCTFail("Expected BigModelError")
        } catch let error as BigModelError {
            let desc = error.errorDescription ?? ""
            XCTAssertTrue(desc.contains("401"))
            XCTAssertTrue(desc.contains("Unauthorized"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTranscribeServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Internal Server Error".utf8))
        }

        do {
            _ = try await sut.transcribe(fileURL: tempAudioURL)
            XCTFail("Expected error")
        } catch is BigModelError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Invalid JSON

    func testTranscribeInvalidJSON() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        do {
            _ = try await sut.transcribe(fileURL: tempAudioURL)
            XCTFail("Expected decoding error")
        } catch is DecodingError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Request format

    func testRequestContainsBearerToken() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {"id": "x", "created": 0, "text": "ok"}
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

        _ = try await sut.transcribe(fileURL: tempAudioURL)

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
    }

    func testRequestBodyContainsModelField() async throws {
        var capturedBody: Data?
        let json = """
        {"id": "x", "created": 0, "text": "ok"}
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

        _ = try await sut.transcribe(fileURL: tempAudioURL)

        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("glm-asr-2512"))
    }

    // MARK: - BigModelError description

    func testBigModelErrorDescription() {
        let error = BigModelError.requestFailed(statusCode: 403, message: "Forbidden")
        XCTAssertEqual(error.errorDescription, "BigModel API error (403): Forbidden")
    }
}
