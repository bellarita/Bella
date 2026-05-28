import Foundation

struct OpenAIClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-5.4-mini"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(messages: [Message], apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIResponsesRequest(messages: messages, model: model))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIClientError.apiError(Self.decodeAPIError(from: data, statusCode: httpResponse.statusCode))
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        if let text = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        let nestedText = decoded.output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let nestedText, !nestedText.isEmpty else {
            throw OpenAIClientError.emptyOutput
        }

        return nestedText
    }

    private static func decodeAPIError(from data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
            return decoded.error.message
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }

        return "OpenAI API 请求失败，状态码：\(statusCode)"
    }
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let input: [InputMessage]

    init(messages: [Message], model: String) {
        self.model = model
        self.input = messages.map { message in
            InputMessage(
                role: message.isUser ? "user" : "assistant",
                content: message.text
            )
        }
    }
}

private struct InputMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OutputItem: Decodable {
    let content: [OutputContent]?
}

private struct OutputContent: Decodable {
    let text: String?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在设置里填写 OpenAI API Key。"
        case .invalidResponse:
            return "OpenAI API 返回了无效响应。"
        case .apiError(let message):
            return message
        case .emptyOutput:
            return "OpenAI API 没有返回可显示的内容。"
        }
    }
}
