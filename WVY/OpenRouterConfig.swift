import Foundation
import Security

struct OpenRouterModel: Identifiable, Codable, Hashable {
    let id: String
}

struct OpenRouterChatMessage: Codable, Hashable {
    let role: String
    let content: String
}

enum OpenRouterConfig {
    static let unavailableModelMessage = "this model is currently unavailable"

    static let models: [OpenRouterModel] = [
        OpenRouterModel(id: "minimax/minimax-m2.5"),
        OpenRouterModel(id: "minimax/minimax-m2.7"),
        OpenRouterModel(id: "google/gemini-3-flash-preview"),
        OpenRouterModel(id: "google/gemma-4-31b-it"),
        OpenRouterModel(id: "xiaomi/mimo-v2-pro"),
        OpenRouterModel(id: "xiaomi/mimo-v2-omni"),
        OpenRouterModel(id: "qwen/qwen3.6-plus"),
        OpenRouterModel(id: "qwen/qwen3.5-9b"),
        OpenRouterModel(id: "z-ai/glm-5.1"),
        OpenRouterModel(id: "z-ai/glm-4.5-air"),
        OpenRouterModel(id: "moonshotai/kimi-k2.5"),
        OpenRouterModel(id: "x-ai/grok-4.1-fast"),
        OpenRouterModel(id: "x-ai/grok-4-fast"),
        OpenRouterModel(id: "openai/gpt-5.4-nano"),
        OpenRouterModel(id: "stepfun/step-3.5-flash"),
        OpenRouterModel(id: "meta-llama/llama-3.1-8b-instruct"),
        OpenRouterModel(id: "arcee-ai/trinity-large-thinking"),
        OpenRouterModel(id: "mistralai/mistral-small-3.2-24b-instruct"),
        OpenRouterModel(id: "openai/gpt-4o-mini"),
        OpenRouterModel(id: "x-ai/grok-4.20"),
        OpenRouterModel(id: "x-ai/grok-4.20-multi-agent"),
        OpenRouterModel(id: "openai/gpt-5.2"),
        OpenRouterModel(id: "openai/gpt-5.4"),
        OpenRouterModel(id: "openai/gpt-4o-2024-05-13"),
        OpenRouterModel(id: "anthropic/claude-opus-4.7"),
        OpenRouterModel(id: "anthropic/claude-haiku-4.5"),
        OpenRouterModel(id: "nvidia/nemotron-3-super-120b-a12b:free"),
        OpenRouterModel(id: "z-ai/glm-4.5-air:free"),
        OpenRouterModel(id: "google/gemma-4-26b-a4b-it:free"),
        OpenRouterModel(id: "google/gemma-3-27b-it:free"),
        OpenRouterModel(id: "google/gemma-4-31b-it:free"),
        OpenRouterModel(id: "google/gemma-3-4b-it:free"),
        OpenRouterModel(id: "google/gemma-3-12b-it:free"),
        OpenRouterModel(id: "google/gemma-3n-e2b-it:free"),
        OpenRouterModel(id: "google/gemma-3n-e4b-it:free"),
        OpenRouterModel(id: "nvidia/nemotron-3-nano-30b-a3b:free"),
        OpenRouterModel(id: "nvidia/nemotron-nano-9b-v2:free"),
        OpenRouterModel(id: "liquid/lfm-2.5-1.2b-instruct:free"),
        OpenRouterModel(id: "liquid/lfm-2.5-1.2b-thinking:free"),
        OpenRouterModel(id: "cognitivecomputations/dolphin-mistral-24b-venice-edition:free"),
        OpenRouterModel(id: "meta-llama/llama-3.3-70b-instruct:free"),
        OpenRouterModel(id: "meta-llama/llama-3.2-3b-instruct:free"),
        OpenRouterModel(id: "nousresearch/hermes-3-llama-3.1-405b:free"),
    ]

    static let defaultModelID = models.first?.id ?? ""
    static let defaultInstructionPrompt = "You are WVY."
    static let autonomousUserPrompt = "You are an autonomous agent, you make every decision on your own, please refer to your perspective to take action"

    static func buildPerspectivePrompt(
        identityPrompt: String,
        instructionPrompt: String,
        currentChatLog: String
    ) -> String {
        """
        Perspective = \"\"\"

        Your Identity:
        \(identityPrompt)

        Your Instructions:
        \(instructionPrompt)

        The Current Chat:
        \(currentChatLog)

        \"\"\"
        """
    }

    static func buildRestReflectionPrompt(
        currentChatLog: String,
        recommendedSleepMinutes: Int
    ) -> String {
        """
        Please reflect on the chat & respond with the number of minutes you would like to rest before sending another reply:
        \(currentChatLog)

        *Recommended \(recommendedSleepMinutes) minutes*
        """
    }

    static func normalizedModelID(
        _ modelID: String,
        availableModels: [OpenRouterModel] = models
    ) -> String {
        let deduplicated = deduplicatedModels(availableModels)

        guard !deduplicated.isEmpty else {
            return defaultModelID
        }

        if deduplicated.contains(where: { $0.id == modelID }) {
            return modelID
        }

        return deduplicated[0].id
    }

    static func deduplicatedModels(_ models: [OpenRouterModel]) -> [OpenRouterModel] {
        var seen = Set<String>()

        return models.filter { model in
            seen.insert(model.id).inserted
        }
    }
}

enum WVYSettingsKey {
    static let selectedModelID = "wvy.selectedModelID"
    static let instructionPrompt = "wvy.instructionPrompt"
    static let agents = "wvy.agents"
    static let maxRepliesPerAgent = "wvy.maxRepliesPerAgent"
    static let appearanceMode = "wvy.appearanceMode"
    static let autonomyMode = "wvy.autonomyMode"
    static let freeWillToolUseEnabled = "wvy.freeWillToolUseEnabled"
    static let fileManagementEnabled = "wvy.fileManagementEnabled"
    static let dataSharingEnabled = "wvy.dataSharingEnabled"
    static let youtubeAutoplayEnabled = "wvy.youtubeAutoplayEnabled"
    static let ttsVoice = "wvy.ttsVoice"
    static let ttsVolume = "wvy.ttsVolume"
}

enum OpenRouterSecrets {
    private static let service = "WVY.OpenRouter"
    private static let account = "apiKey"

    static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard
            status == errSecSuccess,
            let data = item as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return apiKey
    }

    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if trimmedAPIKey.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(trimmedAPIKey.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
}

enum OpenRouterService {
    private static let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    static func validateAPIKey(_ apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let _: OpenRouterModelsResponse = try await perform(request)
    }

    static func sendChat(
        perspectivePrompt: String,
        modelID: String,
        apiKey: String
    ) async throws -> String {
        let messages = [
            OpenRouterChatMessage(role: "system", content: perspectivePrompt),
            OpenRouterChatMessage(role: "user", content: OpenRouterConfig.autonomousUserPrompt)
        ]

        let body = OpenRouterChatRequest(
            model: modelID,
            messages: messages,
            stream: false
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let response: OpenRouterChatResponse = try await perform(request)
        let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !content.isEmpty else {
            throw OpenRouterServiceError.invalidResponse
        }

        return content
    }

    private static func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data)
            let message = apiError?.error?.message ?? apiError?.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenRouterServiceError.requestFailed(message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenRouterServiceError.invalidResponse
        }
    }
}

private struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessage]
    let stream: Bool
}

private struct OpenRouterChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterErrorResponse: Decodable {
    let error: ErrorBody?
    let message: String?

    struct ErrorBody: Decodable {
        let message: String?
    }
}

private enum OpenRouterServiceError: LocalizedError {
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}
