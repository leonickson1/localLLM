//
//  OpenAICompatibleService.swift
//  LocalLLM
//
//  Connects to any server that speaks the OpenAI Chat Completions API.
//  Targets: llama-server, vLLM, LM Studio, Ollama /v1, plus cloud providers
//  (OpenAI, OpenRouter, Together, Fireworks, Groq, Mistral, Anyscale, etc.).
//
//  Spec reference:
//    - POST {baseURL}/v1/chat/completions  (request + streaming SSE)
//    - GET  {baseURL}/v1/models             (model listing)
//

import Foundation
import Combine

@MainActor
class OpenAICompatibleService: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                isConnected = false
                error = nil
            }
        }
    }
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }
    @Published var apiKey: String {
        didSet {
            if apiKey.isEmpty {
                KeychainHelper.delete(account: Self.apiKeyAccount)
            } else {
                KeychainHelper.save(apiKey, account: Self.apiKeyAccount)
            }
        }
    }
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Self.selectedModelKey) }
    }
    @Published var allowSelfSignedCerts: Bool {
        didSet {
            UserDefaults.standard.set(allowSelfSignedCerts, forKey: Self.allowSelfSignedKey)
            // Rebuild the session next time it is used
            cachedSession = nil
        }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var isChecking = false
    @Published private(set) var isGenerating = false
    @Published private(set) var availableModels: [String] = []
    @Published var error: String?

    // MARK: - UserDefaults keys

    private static let enabledKey       = "openai_compat_enabled"
    private static let baseURLKey       = "openai_compat_base_url"
    private static let apiKeyKey        = "openai_compat_api_key"          // legacy, used only for one-time migration
    private static let apiKeyAccount    = "openai_compat_api_key"          // Keychain account name
    private static let selectedModelKey = "openai_compat_selected_model"
    private static let allowSelfSignedKey = "openai_compat_allow_self_signed"

    // MARK: - URLSession with optional self-signed cert acceptance

    private var cachedSession: URLSession?
    private var sessionDelegate: InsecureSessionDelegate?

    private var urlSession: URLSession {
        if let cached = cachedSession { return cached }
        if allowSelfSignedCerts {
            let delegate = InsecureSessionDelegate()
            self.sessionDelegate = delegate
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            cachedSession = session
            return session
        } else {
            cachedSession = URLSession.shared
            return URLSession.shared
        }
    }

    // MARK: - Init

    init() {
        self.isEnabled    = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.baseURL      = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "http://192.168.1.100:8080"
        self.selectedModel = UserDefaults.standard.string(forKey: Self.selectedModelKey) ?? ""
        self.allowSelfSignedCerts = UserDefaults.standard.bool(forKey: Self.allowSelfSignedKey)

        // Load API key from Keychain. If there is a legacy UserDefaults key, migrate it
        // into the Keychain and wipe the UserDefaults copy. This runs once.
        if let migrated = UserDefaults.standard.string(forKey: Self.apiKeyKey), !migrated.isEmpty {
            KeychainHelper.save(migrated, account: Self.apiKeyAccount)
            UserDefaults.standard.removeObject(forKey: Self.apiKeyKey)
            self.apiKey = migrated
        } else {
            self.apiKey = KeychainHelper.load(account: Self.apiKeyAccount) ?? ""
        }

        if isEnabled {
            Task { await checkConnection() }
        }
    }

    // MARK: - URL normalization

    /// Returns the base URL with trailing slash removed and a trailing /v1 suffix removed
    /// (we add the /v1/... path explicitly per endpoint to avoid double-pathing).
    private var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if url.hasSuffix("/v1") { url.removeLast(3) }
        return url
    }

    private func makeURL(_ path: String) -> URL? {
        URL(string: normalizedBaseURL + path)
    }

    private func authorizedRequest(url: URL, method: String, body: Data? = nil, timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = timeout
        if let body = body { req.httpBody = body }
        return req
    }

    // MARK: - Connection check + model listing

    /// GET /v1/models. Populates availableModels and sets isConnected.
    /// Falls back to "connected but model list unknown" if /v1/models is unsupported (some servers).
    func checkConnection() async {
        guard isEnabled else {
            isConnected = false
            return
        }
        isChecking = true
        defer { isChecking = false }

        guard let url = makeURL("/v1/models") else {
            isConnected = false
            error = "Invalid server URL"
            return
        }

        let request = authorizedRequest(url: url, method: "GET", timeout: 8)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                isConnected = false
                error = "No response from server"
                return
            }

            switch http.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let modelsArray = json["data"] as? [[String: Any]] {
                    availableModels = modelsArray.compactMap { $0["id"] as? String }
                    if selectedModel.isEmpty, let first = availableModels.first {
                        selectedModel = first
                    }
                } else {
                    // Endpoint returned 200 but unexpected shape — still treat as connected
                    availableModels = []
                }
                isConnected = true
                error = nil
                print("[OpenAICompat] Connected. \(availableModels.count) models reported.")
            case 401, 403:
                isConnected = false
                error = "Authentication failed. Check your API key."
            case 404:
                // Server is reachable but /v1/models is not supported. That is OK — we can still try chat.
                isConnected = true
                availableModels = []
                error = nil
                print("[OpenAICompat] Server reachable but /v1/models not supported. Manual model name required.")
            default:
                isConnected = false
                error = "Server returned status \(http.statusCode)"
            }
        } catch let urlError as URLError {
            isConnected = false
            switch urlError.code {
            case .notConnectedToInternet: error = "No network connection"
            case .timedOut:                error = "Server did not respond in time"
            case .cannotConnectToHost:     error = "Cannot reach the server. Check the URL and that it is running."
            case .cannotFindHost:          error = "Server hostname not found"
            case .secureConnectionFailed:  error = "HTTPS connection failed. Self-signed certs are not supported, use http for local servers."
            default:                       error = "Connection failed: \(urlError.localizedDescription)"
            }
        } catch {
            isConnected = false
            self.error = "Connection failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Non-streaming chat

    func chat(systemPrompt: String, userMessage: String, model: String? = nil) async -> String? {
        guard isEnabled && isConnected else { return nil }
        let modelName = model ?? selectedModel
        guard !modelName.isEmpty else {
            error = "No model selected"
            return nil
        }

        let payload: [String: Any] = [
            "model": modelName,
            "messages": buildMessages(systemPrompt: systemPrompt, userMessage: userMessage),
            "stream": false
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url  = makeURL("/v1/chat/completions") else {
            error = "Could not encode request"
            return nil
        }

        let request = authorizedRequest(url: url, method: "POST", body: body, timeout: 120)

        isGenerating = true
        defer { isGenerating = false }

        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status != 200 {
                self.error = parseErrorMessage(from: data) ?? "Server returned status \(status)"
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            self.error = "Unexpected response format"
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Streaming chat (SSE)

    /// POST /v1/chat/completions with stream:true. Yields content deltas as they arrive.
    /// Parses Server-Sent Events:
    ///   data: { ... "delta": { "content": "..." } ... }
    ///   data: [DONE]
    func streamChat(systemPrompt: String, userMessage: String, model: String? = nil) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard isEnabled && isConnected else {
                    continuation.finish()
                    return
                }
                let modelName = model ?? selectedModel
                guard !modelName.isEmpty else {
                    await MainActor.run { self.error = "No model selected" }
                    continuation.finish()
                    return
                }

                let payload: [String: Any] = [
                    "model": modelName,
                    "messages": buildMessages(systemPrompt: systemPrompt, userMessage: userMessage),
                    "stream": true
                ]

                guard let body = try? JSONSerialization.data(withJSONObject: payload),
                      let url  = makeURL("/v1/chat/completions") else {
                    await MainActor.run { self.error = "Could not encode request" }
                    continuation.finish()
                    return
                }

                let request = authorizedRequest(url: url, method: "POST", body: body, timeout: 120)

                await MainActor.run { self.isGenerating = true }

                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    // If the server returned a non-200, read the body and surface the error.
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 8192 { break }
                        }
                        let msg = parseErrorMessage(from: errorData) ?? "Server returned status \(http.statusCode)"
                        await MainActor.run { self.error = msg }
                        await MainActor.run { self.isGenerating = false }
                        continuation.finish()
                        return
                    }

                    // SSE parsing. Each event is one or more `data: ...` lines separated from the next by a blank line.
                    // We process line by line and ignore non-data lines (event:, id:, retry:, comments starting with :).
                    for try await line in bytes.lines {
                        // Skip comments and unrelated SSE fields
                        if line.isEmpty { continue }
                        if line.hasPrefix(":") { continue }
                        if line.hasPrefix("event:") || line.hasPrefix("id:") || line.hasPrefix("retry:") { continue }

                        // Only handle data: lines
                        guard line.hasPrefix("data:") else { continue }

                        // Strip "data:" prefix and any single space after it
                        var dataPart = String(line.dropFirst(5))
                        if dataPart.hasPrefix(" ") { dataPart.removeFirst() }

                        // Termination sentinel
                        if dataPart == "[DONE]" { break }

                        // Parse the JSON chunk
                        guard let chunkData = dataPart.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else {
                            continue
                        }

                        // Handle inline error events some providers emit
                        if let errObj = json["error"] as? [String: Any],
                           let msg = errObj["message"] as? String {
                            await MainActor.run { self.error = msg }
                            break
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first else { continue }

                        // Extract content delta (may be missing on role-only initial chunks or finish chunks)
                        if let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                } catch let urlError as URLError {
                    let msg: String
                    switch urlError.code {
                    case .timedOut:            msg = "Server stopped responding"
                    case .networkConnectionLost: msg = "Network connection dropped"
                    case .cancelled:           msg = ""  // user cancelled, don't show
                    default:                   msg = urlError.localizedDescription
                    }
                    if !msg.isEmpty {
                        await MainActor.run { self.error = msg }
                    }
                } catch {
                    await MainActor.run { self.error = error.localizedDescription }
                }

                await MainActor.run { self.isGenerating = false }
                continuation.finish()
            }
        }
    }

    // MARK: - Structured extraction (sync wrapper, same as chat for now)

    func extractStructured(systemPrompt: String, userMessage: String, model: String? = nil) async -> String? {
        return await chat(systemPrompt: systemPrompt, userMessage: userMessage, model: model)
    }

    // MARK: - Helpers

    private func buildMessages(systemPrompt: String, userMessage: String) -> [[String: String]] {
        var messages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    /// Parse the standard OpenAI error envelope: `{"error": {"message": "...", "type": "...", "code": "..."}}`.
    /// Falls back to a top-level "error" string (some servers use that), then nil.
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
            return msg
        }
        if let errStr = json["error"] as? String {
            return errStr
        }
        return nil
    }
}

// MARK: - Self-signed cert delegate

/// URLSession delegate that accepts any server certificate.
/// ONLY used when the user explicitly enables "Allow self-signed certificates" in Settings.
/// This is for users running llama-server / vLLM with locally-generated TLS certs on their LAN.
private final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
