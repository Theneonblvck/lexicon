import Foundation

/// Central configuration. All three cascade model ids are swappable constants
/// (the runtime cascade itself is wired in Step 3). The API key is read ONLY
/// from the environment or the macOS Keychain — never hardcoded.
enum AppConfig {

    // MARK: Runtime model cascade (cheapest sufficient model per analysis tick)
    static let tier1Model = "claude-haiku-4-5-20251001" // hot path, every tick
    static let tier2Model = "claude-sonnet-4-6"          // escalation
    static let tier3Model = "claude-opus-4-8"            // on-demand deep rewrite

    // MARK: Anthropic API
    static let apiBaseURL = "https://api.anthropic.com/v1/messages"
    static let anthropicVersion = "2023-06-01"

    // MARK: Identity / storage
    static let bundleIdentifier = "com.lexicon.app"
    static let keychainService = "com.lexicon.app.apikey"
    static let keychainAccount = "anthropic"

    /// API key resolution order: LEXICON_API_KEY env var → Keychain. Returns nil
    /// when unconfigured. (Unused until Step 3, but the accessor is the contract.)
    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["LEXICON_API_KEY"],
           !env.isEmpty {
            return env
        }
        return Keychain.read(service: keychainService, account: keychainAccount)
    }

    static var apiKeyConfigured: Bool { apiKey != nil }
}
