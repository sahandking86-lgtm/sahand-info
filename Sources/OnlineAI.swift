//
//  OnlineAI.swift
//
//  The call to whichever assistant is selected - Google's Gemini API or Groq's OpenAI-shaped one -
//  and, more importantly, what gets said when it does not work.
//
//  Every failure used to come back as one string: "Gemini isn't available right now - check your
//  connection". A wrong key, no quota, airplane mode and a rejected request all looked identical,
//  which sends you checking WiFi that is fine. Failures are named here, they are named *per provider*
//  (telling someone to visit aistudio.google.com while Groq is selected is a dead end), and the ones
//  a person can fix say what to fix. The key is trimmed and sanity-checked on the way out, since a
//  space picked up while pasting used to look exactly like a network problem.
//
//  Both providers are reached through the same three steps - fold the conversation into a legal turn
//  order, wrap it in the shape that service expects, read the answer out of it - and neither the turn
//  rules nor the error handling is duplicated for the second one.
//

import Foundation

enum AIFailure: Equatable {
    case noKey
    case keyLooksWrong(String)
    case rejected(IntegerValue)          // 401 / 403
    case badRequest(IntegerValue, String?)  // 400, plus whatever Google said why
    case modelUnavailable(String)        // 404
    case rateLimited
    case serverBusy
    case offline
    case timeout
    case cancelled
    case blockedBySecurity
    case badResponse
    /// The model answered with 200 and nothing usable: a safety refusal, or an answer that ran out of
    /// tokens in the middle. Both need saying, not reporting as a parse failure.
    case refusedByModel(String)
    case cutOff

    /// Every string here used to name Google. With a second assistant to choose from, a message that
    /// says "check aistudio.google.com" while Groq is selected sends people to the wrong website, so
    /// the provider is passed in and the wording follows it.
    func message(for provider: AIProvider) -> String {
        switch self {
        case .noKey:
            return "Add your \(provider.shortName) API key in Settings first, then ask again."
        case .keyLooksWrong(let why):
            return "Your API key doesn't look usable — \(why). Open Settings → AI Assistant, paste the whole key again and tap Test."
        case .rejected:
            return "\(provider.shortName) rejected that key (401/403). It may be expired, or not a key from \(provider.keyPage). Check it in Settings and tap Test."
        case .badRequest(_, let detail):
            let why = detail ?? provider.badRequestHint
            return "\(provider.shortName) didn't accept the request (400). \(why)"
        case .modelUnavailable(let model):
            return "The model \"\(model)\" isn't available to your key. Pick another one in Settings, or get a key from \(provider.keyPage)."
        case .rateLimited:
            return provider.rateLimitedHint
        case .serverBusy:
            return "\(provider.shortName) was busy (I retried). Ask again in a moment."
        case .offline:
            return "No internet connection — I retried and couldn't reach \(provider.shortName). Turn on Wi-Fi or mobile data and ask again."
        case .timeout:
            return "That took too long and I stopped waiting, so nothing was changed. Ask again, or shorten what you're asking for."
        case .cancelled:
            return "Stopped."
        case .blockedBySecurity:
            return "iOS blocked the request to \(provider.shortName) (App Transport Security). Nothing was changed."
        case .badResponse:
            return "\(provider.shortName) answered, but not in a form I could read. Nothing was changed."
        case .refusedByModel(let reason):
            return "\(provider.shortName)'s safety filter refused that request (\(reason)), so there is no answer. Nothing was changed."
        case .cutOff:
            return "The answer ran out of room before it finished, so I didn't use a half-finished one. Ask for less at a time and I'll try again."
        }
    }

    var retryable: Bool {
        switch self {
        case .rateLimited, .serverBusy, .offline, .timeout: return true
        default: return false
        }
    }
}

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
}

/// Which brain answers, and where the key comes from. Two were chosen deliberately, not generically:
/// a picker over a hundred models is a research project, while these two cover the real trade.
///
/// Google stays because it works today and needs no card. Groq is here for two reasons. The first is
/// capability: the app had been talking to a *Flash-Lite* model, the smallest one in the family, while
/// a 117-billion-parameter reasoning model is available free. The second is the one that matters for a
/// notebook of passwords - Google's free tier states that prompts and outputs "may be used to improve
/// Google products" and its terms allow human reviewers to read API input and output, whereas Groq's
/// no-training promise is a clause in its Services Agreement (4.2), inference requests are not retained
/// by default, and Zero Data Retention is a toggle any account can reach. Both tiers clear the twenty
/// requests a day this app needs many times over; Groq's is about 1,000 requests and 200,000 tokens a
/// day, and the token ceiling is the one that binds when whole notebooks are being sent.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini
    case groq

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .gemini: return "Google"
        case .groq: return "Groq"
        }
    }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini - Google AI Studio"
        case .groq: return "Groq - gpt-oss 120B, Llama"
        }
    }

    var keyPage: String {
        switch self {
        case .gemini: return "aistudio.google.com/apikey"
        case .groq: return "console.groq.com/keys"
        }
    }

    /// Only used to warn about a paste from the wrong website. Deliberately not enforced: blocking on a
    /// prefix is how someone gets locked out of their own notebook when a provider changes its key
    /// format, and the server rejects a wrong key in a heartbeat anyway.
    var keyPrefix: String? {
        switch self {
        case .gemini: return "AIza"
        case .groq: return "gsk_"
        }
    }

    /// Listed best-first, so the default is the strongest thing each provider gives away.
    var models: [String] {
        switch self {
        case .gemini: return ["gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash"]
        case .groq: return ["openai/gpt-oss-120b", "llama-3.3-70b-versatile", "qwen/qwen3-32b",
                            "meta-llama/llama-4-scout-17b-16e-instruct"]
        }
    }

    var defaultModel: String { models[0] }

    /// Said out loud next to the key field, because "free" is not one policy and a person choosing
    /// between these two is, in practice, choosing what happens to their text.
    var dataPolicy: String {
        switch self {
        case .gemini:
            return "On the free tier Google may use what you send it to improve its products, and its terms allow human reviewers to read API input and output. Turning on billing with the same key stops that. If a note holds a password, this is the tier to keep it off."
        case .groq:
            return "Groq's Services Agreement says it is not permitted to use what you send or receive to train a model, and inference requests are not retained by default - the promise is in the contract, not a page it can edit. A Zero Data Retention toggle in its console switches off even the troubleshooting logs."
        }
    }

    var rateLimitedHint: String {
        switch self {
        case .gemini:
            return "Google's free tier throttles this model and the retry did not get through. Wait half a minute and ask again."
        case .groq:
            return "Groq's free tier stopped that request - either 30 in one minute or today's allowance of about 1,000 requests and 200,000 tokens. The daily count resets at midnight UTC; ask again later, or shorten what you send."
        }
    }

    var badRequestHint: String {
        switch self {
        case .gemini:
            return "That usually means the key belongs to a project with the Generative Language API switched off."
        case .groq:
            return "That usually means the model name is not one Groq offers your key, or the request was too large - try a smaller list of notes."
        }
    }

    /// Google's shape (contents/parts, a separate systemInstruction) versus the OpenAI-shaped body that
    /// everyone else settled on (messages with a system turn, model named inside the JSON).
    var usesGoogleShape: Bool { self == .gemini }

    var keyFieldLabel: String { self == .gemini ? "Gemini API key" : "Groq API key" }

    func endpoint(model: String) -> URL? {
        switch self {
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1/chat/completions")
        }
    }
}

enum OnlineAI {
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
                       notePattern: String = "",
                       provider: AIProvider = .gemini,
                       model: String? = nil) async -> AIOutcome {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.noKey) }
        if let problem = keyProblem(key) { return .failure(.keyLooksWrong(problem)) }

        // Gemini rejects the whole request unless turns alternate user/model and start with "user".
        // The app can legitimately end up with two model turns in a row (a declined confirmation, a
        // card answered from the input bar), so the conversation is folded into a legal shape rather
        // than sent as-is and answered with a 400 nobody can explain.
        var contents: [[String: Any]] = []
        var pendingUser: [String] = []
        var pendingModel: [String] = []
        func flush() {
            if !pendingUser.isEmpty {
                contents.append(["role": "user", "parts": [["text": pendingUser.joined(separator: "\n")]]])
                pendingUser = []
            }
            if !pendingModel.isEmpty {
                contents.append(["role": "model", "parts": [["text": pendingModel.joined(separator: "\n")]]])
                pendingModel = []
            }
        }
        // A conversation must open with the user's turn, so leading model lines are skipped.
        for turn in history.suffix(16).drop(while: { $0.role == "model" }) {
            if turn.role == "model" { pendingModel.append(turn.text) } else { pendingUser.append(turn.text) }
            if pendingUser.isEmpty != pendingModel.isEmpty { continue }
            if !pendingUser.isEmpty, !pendingModel.isEmpty { flush() }
        }
        flush()
        // Whatever the history ended as, the message being asked now is the user's turn.
        if let last = contents.last, (last["role"] as? String) == "user" {
            // Fold the question into that turn instead of producing two user turns in a row.
            if let parts = last["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String {
                contents[contents.count - 1] = ["role": "user", "parts": [["text": text + "\n" + question]]]
            }
        } else {
            contents.append(["role": "user", "parts": [["text": question]]])
        }

        let prompt = AIProtocol.systemPrompt(notes: relevantNotes,
                                             notePattern: notePattern.isEmpty ? nil : notePattern,
                                             includeCategoryTagging: true,
                                             includeReminderTagging: true,
                                             notesAreComplete: true,
                                             contextBudget: contextBudget,
                                             relevantIDs: Set(QuestionAnswerer.topMatchingNotes(for: question,
                                                                                                in: relevantNotes,
                                                                                                limit: 8).map { $0.id }))
        let body = requestBody(provider: provider,
                              model: model ?? provider.defaultModel,
                              contents: contents,
                              system: prompt)
        return await sendRequest(body: body, apiKey: key, provider: provider,
                                model: model ?? provider.defaultModel)
    }

    /// One conversation, two shapes. The folding that makes the turn order legal is shared, so a
    /// second provider cannot quietly have different conversation rules than the first; only the
    /// envelope differs. For the OpenAI-shaped services the instructions become a leading `system`
    /// turn and the model travels inside the body, while Gemini takes it in the URL and a separate
    /// `systemInstruction` field.
    private static func requestBody(provider: AIProvider,
                                   model: String,
                                   contents: [[String: Any]],
                                   system: String?,
                                   maxOutputTokens: Int? = nil) -> [String: Any] {
        if provider.usesGoogleShape {
            var body: [String: Any] = ["contents": contents]
            if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
            if let maxOutputTokens { body["generationConfig"] = ["maxOutputTokens": maxOutputTokens] }
            return body
        }
        var messages: [[String: Any]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        for turn in contents {
            let role = (turn["role"] as? String) == "model" ? "assistant" : "user"
            let parts = turn["parts"] as? [[String: Any]] ?? []
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { continue }
            messages.append(["role": role, "content": text])
        }
        var body: [String: Any] = ["model": model, "messages": messages]
        if let maxOutputTokens { body["max_tokens"] = maxOutputTokens }
        return body
    }

    /// A focused call that only suggests a bilingual category for a note being typed. Failures are
    /// silent by design - a missing tag should never interrupt writing - but the timeout is not.
    static func suggestCategory(title: String, body noteBody: String, apiKey: String,
                               provider: AIProvider = .gemini, model: String? = nil) async -> (en: String, ku: String)? {
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
        let contents: [[String: Any]] = [["role": "user", "parts": [["text": prompt]]]]
        let namedModel = model ?? provider.defaultModel
        let body = requestBody(provider: provider, model: namedModel, contents: contents, system: nil)
        guard case .reply(let text) = await sendRequest(body: body, apiKey: key, provider: provider,
                                                         model: namedModel, attempts: 2) else { return nil }
        guard let object = AIProtocol.jsonObject(in: text),
              let categoryEnglish = object["category_en"] as? String,
              !categoryEnglish.isEmpty else { return nil }
        return (en: categoryEnglish, ku: (object["category_ku"] as? String) ?? "")
    }

    /// Settings' "Test" button: a one-token request that answers the only question that matters -
    /// is this key usable from this phone, right now?
    static func verifyKey(_ rawKey: String, provider: AIProvider = .gemini,
                          model: String? = nil) async -> AIFailure? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .noKey }
        if let problem = keyProblem(key) { return .keyLooksWrong(problem) }
        let namedModel = model ?? provider.defaultModel
        let contents: [[String: Any]] = [["role": "user", "parts": [["text": "Reply with the single word: ok"]]]]
        let body = requestBody(provider: provider, model: namedModel, contents: contents,
                               system: nil, maxOutputTokens: 5)
        switch await sendRequest(body: body, apiKey: key, provider: provider, model: namedModel, attempts: 1) {
        case .reply: return nil
        case .failure(let failure): return failure
        }
    }

    /// "That is not a Groq key" is worth saying *before* the request fails, but not worth failing
    /// over - a provider changing its key format must not lock someone out of their own notebook.
    static func prefixProblem(_ key: String, provider: AIProvider) -> String? {
        guard !key.isEmpty, let prefix = provider.keyPrefix, !key.hasPrefix(prefix) else { return nil }
        return "it does not start with \(prefix), which is what a \(provider.shortName) key looks like"
    }

    static func keyProblem(_ key: String) -> String? {
        if key.count < 20 { return "it is only \(key.count) characters long" }
        // Saving strips the ends; anything in the middle survives, and a pasted key with a line
        // break in it is a real thing that happens when a browser wraps the text.
        if key.contains(where: { $0 == " " || $0.isNewline }) { return "there is a space or line break inside it" }
        if key.lowercased().hasPrefix("your") { return "it looks like a placeholder rather than a key" }
        return nil
    }

    // MARK: - Shared request

    private static func sendRequest(body: [String: Any], apiKey: String, provider: AIProvider,
                                   model: String, attempts: Int = 3) async -> AIOutcome {
        // No usable URL means the model name was not a URL fragment - the same "the request could not
        // be built" outcome for either provider, phrased without blaming the network.
        guard let url = provider.endpoint(model: model) else { return .failure(.badRequest(0, "the model name could not be turned into a URL")) }

        var lastFailure: AIFailure = .offline
        for attempt in 1...max(1, attempts) {
            if Task.isCancelled { return .failure(.cancelled) }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Google takes the key in a header of its own; the OpenAI-shaped services, Groq among them,
            // take the usual bearer token.
            if provider.usesGoogleShape {
                request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastFailure = .badResponse
                    continue
                }

                if (200...299).contains(http.statusCode) {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return .failure(.badResponse)
                    }
                    if !provider.usesGoogleShape { return openAIReply(from: json) }
                    // A refusal is not a malformed reply. Google says why (safety, or an empty
                    // answer), and "I couldn't read that" sent people hunting for a formatting problem.
                    if let reason = (json["promptFeedback"] as? [String: Any])?["blockReason"] as? String {
                        return .failure(.refusedByModel(reason))
                    }
                    let candidates = json["candidates"] as? [[String: Any]] ?? []
                    let finishReason = candidates.first?["finishReason"] as? String
                    guard let content = candidates.first?["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]]
                    else {
                        return .failure(finishReason == "MAX_TOKENS" ? .cutOff : .badResponse)
                    }
                    let text = parts
                        .filter { ($0["thought"] as? Bool) != true }
                        .compactMap { $0["text"] as? String }
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else {
                        return .failure(finishReason == "MAX_TOKENS" ? .cutOff : .badResponse)
                    }
                    return .reply(text)
                }

                let failure = classify(status: http.statusCode, data: data, model: model)
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

    /// The OpenAI-shaped answer: the text sits in `choices[0].message.content`, and the same
    /// "was it cut off" distinction the Google path makes - a half answer must never be applied to a
    /// note, and must never be shown as if it were finished.
    private static func openAIReply(from json: [String: Any]) -> AIOutcome {
        let choice = (json["choices"] as? [[String: Any]])?.first
        let finishReason = choice?["finish_reason"] as? String
        let content = choice?["message"] as? [String: Any]
        let text = ((content?["content"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure(finishReason == "length" ? .cutOff : .badResponse)
        }
        return .reply(text)
    }

    private static func classify(status: Int, data: Data, model: String) -> AIFailure {
        switch status {
        case 401, 403: return .rejected(IntegerValue(value: status))
        case 400: return .badRequest(IntegerValue(value: status), APIError.readMessage(data: data))
        case 404: return .modelUnavailable(model)
        case 429: return .rateLimited
        case 500...599: return .serverBusy
        default:
            // The API says which field or limit it disliked; that is far more useful than a bare
            // status code, so it is carried into the message rather than dropped.
            if let message = APIError.readMessage(data: data) {
                return .badRequest(IntegerValue(value: status), message)
            }
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
