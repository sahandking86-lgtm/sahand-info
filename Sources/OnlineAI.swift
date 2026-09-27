//
//  OnlineAI.swift
//
//  The only network call this app makes: asking the assistant, and - more importantly - what gets said
//  when it does not work.
//
//  Every failure used to come back as one string: "the model isn't available right now - check your
//  connection". A wrong key, no quota, airplane mode and a rejected request all looked identical, which
//  sends you checking WiFi that is fine. Failures are named here, and the ones a person can fix say
//  what to fix. The key is also trimmed and sanity-checked on the way out, since a space picked up while
//  pasting used to look exactly like a network problem.
//
//  There is exactly one assistant now, and that is a privacy decision rather than a simplification.
//  The provider this used to call stated, in its free-tier terms, that prompts and outputs may be used
//  to improve its products and that reviewers may read API traffic - for a notebook that may contain a
//  password, an unacceptable trade when a stronger model is free elsewhere with the opposite promise.
//  So the other provider, its key field and its request shape were
//  deleted outright: not hidden behind a setting someone could leave wrong, but gone, so no path
//  remains that could send a note there. `Assistant` below is where the next one would be added, and
//  the reason it is cheap is that nothing in here is provider-specific any more except the URL, the
//  header and the two lines that read the answer out of the JSON.
//

import Foundation

/// Everything that is true of the service behind this call. Kept in one place so the policy someone
/// agreed to on their provider's website and the wording shown in Settings can never drift apart.
enum Assistant {
    static let name = "Groq"
    static let keyPage = "console.groq.com/keys"
    static let keyPrefix = "gsk_"

    /// Only used to warn about a paste from the wrong website. Deliberately not enforced: blocking on a
    /// prefix is how someone gets locked out of their own notebook when a provider changes its key
    /// format, and the server rejects a wrong key in a heartbeat anyway.
    static func prefixProblem(_ key: String) -> String? {
        guard !key.isEmpty, !key.hasPrefix(keyPrefix) else { return nil }
        return "it does not start with \(keyPrefix), which is what a \(name) key looks like"
    }

    /// Best first. gpt-oss-120b is a 117-billion-parameter reasoning model; the rest are what to fall
    /// back on when today's quota is spent or a name gets deprecated, and the app reports a bad name
    /// rather than silently swapping one for another.
    ///
    /// Taken from the provider's supported-models page rather than from memory - two names that were
    /// here a day ago (`qwen/qwen3-32b`, `meta-llama/llama-4-scout-17b-16e-instruct`) are no longer on
    /// that list at all, and a model the service has dropped is a 404 the user has to be told about.
    static let models = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
        "qwen/qwen3.8-27b",
    ]

    static var defaultModel: String { models[0] }

    static var endpoint: URL? { URL(string: "https://api.groq.com/openai/v1/chat/completions") }

    /// Said out loud next to the key field, because the thing a person is really accepting when they
    /// paste a key is a data policy, not an endpoint.
    static let dataPolicy = "\(name) does not use what you send it or what comes back to train a model - that is a clause in its services agreement, not a page it can edit - and inference requests are not kept by default. The free plan is rate-limited, so a long notebook spends the token allowance before the request one."

    static let rateLimitedHint = "\(name)'s free tier stopped that request: it allows 30 a minute, about 1,000 a day, and 8,000 tokens a minute - which is the one a long question trips. The daily count resets at midnight UTC; wait a minute and ask again, or ask about fewer notes at a time."

    static let badRequestHint = "That usually means the model name is not one \(name) offers your key, or the request was too large - try a smaller list of notes."
}

enum AIFailure: Equatable {
    case noKey
    case keyLooksWrong(String)
    case rejected(IntegerValue)          // 401 / 403
    case badRequest(IntegerValue, String?)  // 400, plus whatever the service said why
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

    var message: String {
        switch self {
        case .noKey:
            return "Add your \(Assistant.name) API key in Settings first, then ask again."
        case .keyLooksWrong(let why):
            return "Your API key doesn't look usable — \(why). Open Settings → AI Assistant, paste the whole key again and tap Test."
        case .rejected:
            return "\(Assistant.name) rejected that key (401/403). It may be expired, or not a key from \(Assistant.keyPage). Check it in Settings and tap Test."
        case .badRequest(_, let detail):
            let why = detail ?? Assistant.badRequestHint
            return "\(Assistant.name) didn't accept the request (400). \(why)"
        case .modelUnavailable(let model):
            return "The model \"\(model)\" isn't available to your key. Pick another one in Settings, or get a key from \(Assistant.keyPage)."
        case .rateLimited:
            return Assistant.rateLimitedHint
        case .serverBusy:
            return "\(Assistant.name) was busy (I retried). Ask again in a moment."
        case .offline:
            return "No internet connection — I retried and couldn't reach \(Assistant.name). Turn on Wi-Fi or mobile data and ask again."
        case .timeout:
            return "That took too long and I stopped waiting, so nothing was changed. Ask again, or shorten what you're asking for."
        case .cancelled:
            return "Stopped."
        case .blockedBySecurity:
            return "iOS blocked the request to \(Assistant.name) (App Transport Security). Nothing was changed."
        case .badResponse:
            return "\(Assistant.name) answered, but not in a form I could read. Nothing was changed."
        case .refusedByModel(let reason):
            return "\(Assistant.name)'s safety filter refused that request (\(reason)), so there is no answer. Nothing was changed."
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

enum OnlineAI {
    /// Rough ceiling for the note text carried in one request. Past this, bodies are shortened and
    /// the model is told they were - a confident "that isn't in your notes" from a truncated context is
    /// worse than admitting it only saw part of them.
    ///
    /// The number is set by the provider's *per-minute* token limit, not by what the model can swallow:
    /// the free tier allows 8,000 tokens a minute, a prompt of 60,000 characters is roughly 15,000
    /// tokens (Kurdish in Arabic script costs more than that, not less), and such a request is refused
    /// however long you wait between attempts. So the ceiling is sized to arrive comfortably under it -
    /// about a third of a long novel of notes per question - rather than optimistically over a wall.
    static let contextBudget = 16_000

    /// How many times one question may ask for text it was not given. Each lookup is a second request,
    /// and the free tier counts requests per minute as well as tokens, so this is a budget rather than
    /// a limit on curiosity: three is enough to read the two notes a question names, then the one it
    /// turned out to depend on. When they run out the model is told, and answers from what it has read.
    static let lookupRounds = 3

    /// What one lookup may carry. Smaller than the listing on purpose: the request that opens a
    /// conversation already holds every title, so a lookup only has to add text, and keeping each one
    /// well under the ceiling is what makes the whole exchange fit in a minute instead of trading one
    /// refusal for another.
    static let lookupBudget = 5_000

    /// How long one question may take from the moment it is asked before the app stops going back for
    /// more. Without it the loop is worse than the single request it replaced on the *slow* path: the
    /// opening request retries three times at 25 seconds each and every lookup twice more, so a
    /// question on a bad connection could bounce the dots for four minutes. The Stop button is there,
    /// but a wait that needs explaining is a wait that should not happen - so the budget ends the
    /// conversation rather than the user ending it. It only gates lookups: the first request keeps all
    /// its retries, because a setup that answers slowly must still be allowed to answer at all.
    ///
    /// Sixty seconds because that is the window the provider measures in: requests and tokens per
    /// *minute*, so a question that finishes inside one minute is also a question that did not spend
    /// the next one waiting out its own throttle. It is not a judgment about how long an answer should
    /// take - 45 seconds, the number first written here, cut lookups off for anyone whose opening
    /// request had to retry, which is precisely the moment reading is most useful.
    static let questionTimeBudget: TimeInterval = 60

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
                       model: String? = nil) async -> AIOutcome {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.noKey) }
        if let problem = keyProblem(key) { return .failure(.keyLooksWrong(problem)) }

        // The transcript is folded as it is copied: a turn is merged into the previous one whenever
        // they have the same speaker. That is the whole rule, and it is what makes the result safe to
        // send - two assistant lines in a row happen on their own (a failed request leaves one behind,
        // and a confirmation answered from the input bar adds another), an empty content field makes
        // some services answer with a 400 that says nothing useful, and a conversation should not open
        // with the model's voice. Merging on the way in fixes all three without a second pass.
        var messages: [[String: Any]] = []
        func emit(_ role: String, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if role == "assistant", messages.isEmpty { return }
            if let last = messages.last, (last["role"] as? String) == role,
               let existing = last["content"] as? String {
                messages[messages.count - 1] = ["role": role, "content": existing + "\n" + trimmed]
            } else {
                messages.append(["role": role, "content": trimmed])
            }
        }
        for turn in history.suffix(16) {
            emit(turn.role == "model" ? "assistant" : "user", turn.text)
        }
        // Whatever the history ended as, the question being asked now is the user's turn.
        emit("user", question)

        let prompt = AIProtocol.systemPrompt(notes: relevantNotes,
                                             notePattern: notePattern.isEmpty ? nil : notePattern,
                                             includeCategoryTagging: true,
                                             includeReminderTagging: true,
                                             notesAreComplete: true,
                                             contextBudget: contextBudget,
                                             relevantIDs: Set(QuestionAnswerer.topMatchingNotes(for: question,
                                                                                                in: relevantNotes,
                                                                                                limit: 8).map { $0.id }))
        let namedModel = model ?? Assistant.defaultModel
        // The listing is only what fit in the first request, so the conversation is not ended when the
        // model asks for more: the app reads its own snapshot of the notes, answers with the real text,
        // and puts the question again. Nothing on screen moves during a lookup, and the notes it fetches
        // come from the same snapshot as the listing, so an answer cannot straddle two versions of the
        // notebook. Only `read_notes` is answered here; every other action goes back to the app to be
        // carried out or confirmed, exactly as before.
        var round = 0
        // Uptime, not the date: a clock that steps forward for a time-zone change or a daylight-saving
        // jump must not be able to end a conversation that was on its second look.
        let started = ProcessInfo.processInfo.systemUptime
        while true {
            let body = requestBody(model: namedModel, messages: messages, system: prompt)
            // The first request gets the full retries; a follow-up that fails mid-conversation should
            // not spend another minute before saying so.
            let outcome = await sendRequest(body: body, apiKey: key, model: namedModel,
                                            attempts: round == 0 ? 3 : 2)
            guard case .reply(let raw) = outcome else { return outcome }
            let asked = AIProtocol.parse(raw)
            guard asked.action == "read_notes" else { return .reply(raw) }
            guard round < lookupRounds else { return .reply(raw) }
            if ProcessInfo.processInfo.systemUptime - started > questionTimeBudget {
                // Deliberately not the reply, which would render as "ask me once more" and invite the
                // same slow exchange a second time. The timeout message already says what to do about
                // it, and "nothing was changed" is true of a read.
                return .failure(.timeout)
            }

            emit("assistant", raw)
            var fetched = AIProtocol.lookupText(for: asked, in: relevantNotes, budget: lookupBudget)
            if round == lookupRounds - 1 {
                fetched += "\n\nThat was the last lookup this question allows. Answer from what you have read, and say which note you did not get to read rather than guessing about it."
            }
            emit("user", "[from the notes] \(fetched)")
            round += 1
        }
    }

    /// The instructions go in as a leading `system` turn, which is what every OpenAI-shaped service
    /// expects; the model name travels inside the body rather than in the URL.
    private static func requestBody(model: String,
                                   messages: [[String: Any]],
                                   system: String?,
                                   maxOutputTokens: Int? = nil) -> [String: Any] {
        var turns: [[String: Any]] = []
        if let system { turns.append(["role": "system", "content": system]) }
        for turn in messages {
            let text = (turn["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty, let role = turn["role"] as? String else { continue }
            turns.append(["role": role, "content": text])
        }
        var body: [String: Any] = ["model": model, "messages": turns]
        if let maxOutputTokens { body["max_tokens"] = maxOutputTokens }
        return body
    }

    /// A focused call that only suggests a bilingual category for a note being typed. Failures are
    /// silent by design - a missing tag should never interrupt writing - but the timeout is not.
    static func suggestCategory(title: String, body noteBody: String, apiKey: String,
                                model: String? = nil) async -> (en: String, ku: String)? {
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
        let namedModel = model ?? Assistant.defaultModel
        let body = requestBody(model: namedModel,
                              messages: [["role": "user", "content": prompt]],
                              system: nil)
        guard case .reply(let text) = await sendRequest(body: body, apiKey: key, model: namedModel,
                                                         attempts: 2) else { return nil }
        guard let object = AIProtocol.jsonObject(in: text),
              let categoryEnglish = object["category_en"] as? String,
              !categoryEnglish.isEmpty else { return nil }
        return (en: categoryEnglish, ku: (object["category_ku"] as? String) ?? "")
    }

    /// Settings' "Test" button: a small request that answers the only question that matters - is this
    /// key usable from this phone, right now?
    static func verifyKey(_ rawKey: String, model: String? = nil) async -> AIFailure? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .noKey }
        if let problem = keyProblem(key) { return .keyLooksWrong(problem) }
        let namedModel = model ?? Assistant.defaultModel
        // A reasoning model spends the budget on thinking before it speaks, so the handful of tokens
        // that suffice for a one-word answer come back as an empty reply and would be reported as a
        // broken key.
        let body = requestBody(model: namedModel,
                              messages: [["role": "user", "content": "Reply with the single word: ok"]],
                              system: nil, maxOutputTokens: 128)
        switch await sendRequest(body: body, apiKey: key, model: namedModel, attempts: 1) {
        case .reply: return nil
        // "It ran out of room" still proves the thing being tested: the key is accepted and there is
        // quota left. Saying the key is broken because the model thought too long would be a lie.
        case .failure(.cutOff): return nil
        case .failure(let failure): return failure
        }
    }

    /// "That is not a key" is worth saying *before* the request fails, but not worth failing over - a
    /// key that works from somewhere unexpected must stay usable.
    static func keyProblem(_ key: String) -> String? {
        if key.count < 20 { return "it is only \(key.count) characters long" }
        // Saving strips the ends; anything in the middle survives, and a pasted key with a line
        // break in it is a real thing that happens when a browser wraps the text.
        if key.contains(where: { $0 == " " || $0.isNewline }) { return "there is a space or line break inside it" }
        if key.lowercased().hasPrefix("your") { return "it looks like a placeholder rather than a key" }
        return nil
    }

    // MARK: - The request

    private static func sendRequest(body: [String: Any], apiKey: String, model: String,
                                   attempts: Int = 3) async -> AIOutcome {
        // A missing URL is not a network problem, and saying so keeps "check your wifi" out of the
        // one case where wifi was never the issue.
        guard let url = Assistant.endpoint else { return .failure(.badRequest(0, "the request URL could not be built")) }

        var lastFailure: AIFailure = .offline
        for attempt in 1...max(1, attempts) {
            if Task.isCancelled { return .failure(.cancelled) }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                    return reply(from: json)
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

    /// The answer, and the one distinction that has to survive parsing: a reply that ran out of room is
    /// not an answer. Half a rewrite applied to a note, or half a list of them shown as if finished,
    /// is worse than saying it did not complete.
    private static func reply(from json: [String: Any]) -> AIOutcome {
        let choice = (json["choices"] as? [[String: Any]])?.first
        let finishReason = choice?["finish_reason"] as? String
        let message = choice?["message"] as? [String: Any]
        let text = ((message?["content"] as? String) ?? "")
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

/// Small namespace so the error body the service returns is at least read next to the message.
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
