import Foundation

enum LLMBackendProvider: String, CaseIterable {
    case codexCLI = "codex_cli"
    case openAIAPI = "openai_api"
    case azureOpenAI = "azure_openai"

    var displayName: String {
        switch self {
        case .codexCLI:
            return "Pure Chat Mode (Codex CLI)"
        case .openAIAPI:
            return "OpenAI API (ChatGPT)"
        case .azureOpenAI:
            return "Azure OpenAI (Placeholder)"
        }
    }

    var actionButtonTitle: String? {
        switch self {
        case .codexCLI:
            return "Codex Login"
        case .openAIAPI:
            return "Set API Credentials"
        case .azureOpenAI:
            return nil
        }
    }
}
