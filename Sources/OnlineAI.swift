//
//  OnlineAI.swift
//
//  The Gemini call, and - more importantly - what gets said when it does not work.
//
//  Every failure used to come back as one string: "Gemini isn't available right now - check your
//  connection". A wrong key, no quota, airplane mode and a rejected request all looked identical,
//  which sends you checking WiFi that is fine. Failures are named here, and the ones that can be
//  fixed by a person say what to fix. The key is also trimmed and sanity-checked on the way out,
//  since a space picked up while pasting used to look exactly like a network problem.
//

import Foundation

enum AIFailure: Equatable {
    case noKey
    case keyLooksWrong(String)
    case rejected(IntegerValue)          // 401 / 403
    case badRequest(IntegerValue)        // 400
    case modelUnavailable(String)        // 404
    case rateLimited
    case serverBusy
    case offline
    case timeout
    case cancelled
    case blockedBySecurity
    case badResponse

    var message: String {
        switch self {
        case .noKey:
            return "Add your Gemini API key in Settings first, then ask again."
        case .keyLooksWrong(let why):
            return "Your API key doesn't look usable — \(why). Open Settings → AI Assistant, paste the whole key again and tap Test."
        case .rejected:
            return "Google rejected that key (401/403). It may be expired, or not the key from aistudio.google.com/apikey. Check it in Settings and tap Test."
        case .badRequest:
            return "Google didn't accept the request (400). That usually means the key belongs to a project with the Generative Language API switched off."
        case .modelUnavailable(let model):
            return "The model \"\(model)\" isn't available to your key, so there's nothing to ask. Try a key from aistudio.google.com/apikey on a Google AI Studio project."
        case .rateLimited:
            return "The free tier is rate-limited and had to be retried. Wait half a minute and ask again."
        case .serverBusy:
            return "Google's servers were busy (I retried). Ask again in a moment."
        case .offline:
            return "No internet connection — I retried and couldn't reach Google. Turn on Wi-Fi or mobile data and ask again."
        case .timeout:
            return "That took too long and I stopped waiting, so nothing was changed. Ask again, or shorten what you're asking for."
        case .cancelled:
            return "Stopped."
        case .blockedBySecurity:
            return "iOS blocked the request to Google (App Transport Security). Nothing was changed."
        case .badResponse:
            return "Google answered, but not in a form I could read. Nothing was changed."
        }
    }

    var retryable: Bool {
        switch self {
        case .rateLimited, .serverBusy, .offline, .timeout: return true
        default: return false
        }
    }
}

/// Boxed Int so the enum stays Equatable without a synthetic conformance fight.
/// A status code, boxed so `AIFailure` stays Equatable without a synthetic-conformance fight.
struct IntegerValue: Equatable, ExpressibleByIntegerLiteral, CustomStringConvertible, Hashable {
    var value: Int
    init(value: Int) { self.value = value }
    init(integerLiteral: Int) { value = integerLiteral }
    var description: String { String(value) }
}

enum AIOutcome {
    case reply(String)
    case failure(AIFailure)

    var text: String {
        switch self {
        case .reply(let value): return value
        case .failure(let failure): return failure.message
        }
    }
}

enum OnlineAI {
    static let modelName = "gemini-3.5-flash-lite"
    private static var endpoint: URL? {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent")
    }

    /// Rough ceiling for the note text carried in one request. Past this, bodies are shortened and
    /// the model is told they were - a confident "that isn't in your notes" from a truncated context
    /// is worse than admitting it only saw part of them.
    static let contextBudget = 60_000

    private static var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // 25s per attempt, twice: the old default (60s) times three retries could keep the "thinking"
        // dots spinning for the better part of three minutes with no way to stop it.
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 70
        configuration.waitsForConnectivity = false
        configuration.shouldUseExtendedBackgroundIdleMode = false
        return URLSession(configuration: configuration)
    }()

    // MARK: - Public calls

    static func answer(question: String,
                       relevantNotes: [Note],
                       apiKey: String,
                       history: [ConversationTurn] = [],
                       notePattern: String = "") async -> AIOutcome {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.noKey) }
        if let problem = keyProblem(key) { return .failure(.keyLooksWrong(problem)) }

        var contents: [[String: Any]] = history.map { turn in
            ["role": turn.role, "parts": [["text": turn.text]]]
        }
        contents.append(["role": "user", "parts": [["text": question]]])

        let prompt = AIProtocol.systemPrompt(notes: relevantNotes,
                                             notePattern: notePattern.isEmpty ? nil : notePattern,
                                             includeCategoryTagging: true,
                                             includeReminderTagging: true,
                                             notesAreComplete: true,
                                             contextBudget: contextBudget)
        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": prompt]]],
        ]
        return await sendRequest(body: body, apiKey: key)
    }

    /// A focused call that only suggests a bilingual category for a note being typed. Failures are
    /// silent by design - a missing tag should never interrupt writing - but the timeout is not.
    static func suggestCategory(title: String, body noteBody: String, apiKey: String) async -> (en: String, ku: String)? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, keyProblem(key) == nil else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return nil }

        let prompt = """
        You are categorizing a personal note. Respond with ONLY a single JSON object, nothing else - \
        no explanation, no markdown fences: {"category_en": "short English category", "category_ku": \
        "the same category in Kurdish (Central Kurdish / Sorani, Arabic-based script)"}. Keep both to a \
        word or two (e.g. Finance, Health, Passwords, Work, Travel).

        Note title: \(trimmedTitle.isEmpty ? "(untitled)" : trimmedTitle)
        Note body: \(trimmedBody.isEmpty ? "(empty)" : trimmedBody)
        """
        let body: [String: Any] = ["contents": [["role": "user", "parts": [["text": prompt]]]]]
        guard case .reply(let text) = await sendRequest(body: body, apiKey: key, attempts: 2) else { return nil }
        guard let object = AIProtocol.jsonObject(in: text),
              let categoryEnglish = object["category_en"] as? String,
              !categoryEnglish.isEmpty else { return nil }
        return (en: categoryEnglish, ku: (object["category_ku"] as? String) ?? "")
    }

    /// Settings' "Test" button: a one-token request that answers the only question that matters -
    /// is this key usable from this phone, right now?
    static func verifyKey(_ rawKey: String) async -> AIFailure? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .noKey }
        if let problem = keyProblem(key) { return .keyLooksWrong(problem) }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": "Reply with the single word: ok"]]]],
            "generationConfig": ["maxOutputTokens": 5],
        ]
        switch await sendRequest(body: body, apiKey: key, attempts: 1) {
        case .reply: return nil
        case .failure(let failure): return failure
        }
    }

    static func keyProblem(_ key: String) -> String? {
        if key.count < 20 { return "it is only \(key.count) characters long" }
        if key.contains(" ") { return "there is a space in the middle of it" }
        if key.lowercased().hasPrefix("your") { return "it looks like a placeholder rather than a key" }
        return nil
    }

    // MARK: - Shared request

    private static func sendRequest(body: [String: Any], apiKey: String, attempts: Int = 3) async -> AIOutcome {
        guard let url = endpoint else { return .failure(.badRequest(0)) }

        var lastFailure: AIFailure = .offline
        for attempt in 1...max(1, attempts) {
            if Task.isCancelled { return .failure(.cancelled) }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastFailure = .badResponse
                    continue
                }

                if (200...299).contains(http.statusCode) {
                    guard
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let candidates = json["candidates"] as? [[String: Any]],
                        let content = candidates.first?["content"] as? [String: Any],
                        let parts = content["parts"] as? [[String: Any]]
                    else {
                        return .failure(.badResponse)
                    }
                    let text = parts
                        .filter { ($0["thought"] as? Bool) != true }
                        .compactMap { $0["text"] as? String }
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return .failure(.badResponse) }
                    return .reply(text)
                }

                let failure = classify(status: http.statusCode, data: data)
                lastFailure = failure
                // Only the temporary ones are worth retrying; a refused key retried three times just
                // delays the message that says what is wrong.
                guard failure.retryable, attempt < attempts else { return .failure(failure) }
                let backoff = UInt64(attempt) * 2
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch let error as URLError {
                let failure = classify(urlError: error)
                lastFailure = failure
                guard failure.retryable, attempt < attempts else { return .failure(failure) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                lastFailure = .badResponse
            }
        }
        return .failure(lastFailure)
    }

    private static func classify(status: Int, data: Data) -> AIFailure {
        switch status {
        case 401, 403: return .rejected(IntegerValue(value: status))
        case 400: return .badRequest(IntegerValue(value: status))
        case 404: return .modelUnavailable(modelName)
        case 429: return .rateLimited
        case 500...599: return .serverBusy
        default:
            // The API says which field or limit it disliked; that is far more useful than a number.
            if let message = APIError.readMessage(data: data) { return .badRequest(IntegerValue(value: status)) }
            return .badResponse
        }
    }

    private static func classify(urlError: URLError) -> AIFailure {
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
            return .offline
        case .secureConnectionFailed, .badServerResponse: return .blockedBySecurity
        default: return .offline
        }
    }
}

/// Small namespace so the error body Google returns is at least logged next to the message.
enum APIError {
    static func readMessage(data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        return message
    }
}
