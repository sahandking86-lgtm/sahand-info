import Foundation

enum OnlineAI {
    private static let modelURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")

    static func answer(
        question: String,
        relevantNotes: [Note],
        apiKey: String,
        history: [ConversationTurn] = [],
        notePattern: String = ""
    ) async -> String {
        guard !apiKey.isEmpty else {
            return "Add your Gemini API key in Settings first."
        }

        var contents: [[String: Any]] = history.map { turn in
            ["role": turn.role, "parts": [["text": turn.text]]]
        }
        contents.append(["role": "user", "parts": [["text": question]]])

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": AIProtocol.systemPrompt(notes: relevantNotes, notePattern: notePattern.isEmpty ? nil : notePattern, includeCategoryTagging: true, includeReminderTagging: true, notesAreComplete: true)]]
            ]
        ]

        return await sendRequest(body: body, apiKey: apiKey)
    }

    /// A small, focused call just to suggest a bilingual category for a note — used to
    /// auto-tag notes the user writes themselves, separate from the full Ask conversation.
    static func suggestCategory(title: String, body noteBody: String, apiKey: String) async -> (en: String, ku: String)? {
        guard !apiKey.isEmpty else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return nil }

        let prompt = """
        You are categorizing a personal note. Respond with ONLY a single JSON object, nothing else — no explanation, no markdown fences: {"category_en": "short English category", "category_ku": "the same category translated into Kurdish (Central Kurdish / Sorani, Kurdish Arabic-based script)"}. Keep both short — a word or two (e.g. Finance, Health, Passwords, Work, Travel).

        Note title: \(trimmedTitle.isEmpty ? "(untitled)" : trimmedTitle)
        Note body: \(trimmedBody.isEmpty ? "(empty)" : trimmedBody)
        """

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ]
        ]

        let rawText = await sendRequest(body: body, apiKey: apiKey)

        guard
            let firstBrace = rawText.firstIndex(of: "{"),
            let lastBrace = rawText.lastIndex(of: "}"),
            firstBrace < lastBrace
        else {
            return nil
        }

        let jsonSubstring = rawText[firstBrace...lastBrace]
        guard
            let data = jsonSubstring.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let categoryEnglish = obj["category_en"] as? String,
            !categoryEnglish.isEmpty
        else {
            return nil
        }

        let categoryKurdish = (obj["category_ku"] as? String) ?? ""
        return (en: categoryEnglish, ku: categoryKurdish)
    }

    /// Shared request + retry logic used by both answer() and suggestCategory().
    private static func sendRequest(body: [String: Any], apiKey: String) async -> String {
        guard let url = modelURL else {
            return "Invalid API URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let maxAttempts = 3
        var lastErrorMessage = "Something went wrong talking to Gemini."

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastErrorMessage = "No response from Gemini."
                    continue
                }

                if (200...299).contains(http.statusCode) {
                    guard
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let candidates = json["candidates"] as? [[String: Any]],
                        let content = candidates.first?["content"] as? [String: Any],
                        let parts = content["parts"] as? [[String: Any]]
                    else {
                        return "Couldn't parse Gemini's response."
                    }

                    let text = parts
                        .filter { ($0["thought"] as? Bool) != true }
                        .compactMap { $0["text"] as? String }
                        .joined()

                    guard !text.isEmpty else {
                        return "Gemini didn't return any text."
                    }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Overloaded (503) or rate-limited (429): worth a couple of retries with backoff.
                // Anything else (bad key, malformed request, etc.) fails immediately — retrying won't help.
                if http.statusCode == 503 || http.statusCode == 429 {
                    lastErrorMessage = "Gemini is busy right now."
                    if attempt < maxAttempts {
                        let delaySeconds = UInt64(attempt) * 2
                        try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                        continue
                    }
                } else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    return "Gemini returned an error: \(message)"
                }
            } catch {
                lastErrorMessage = "Network error: \(error.localizedDescription)"
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
            }
        }

        return "\(lastErrorMessage) Try again in a bit, or switch to offline mode in Settings."
    }
}
