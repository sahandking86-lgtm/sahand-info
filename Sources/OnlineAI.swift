import Foundation

enum OnlineAI {
    static func answer(question: String, relevantNotes: [Note], apiKey: String) async -> String {
        guard !apiKey.isEmpty else {
            return "Add your Gemini API key in Settings first."
        }

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": question]]]
            ],
            "systemInstruction": [
                "parts": [["text": AIProtocol.systemPrompt(notes: relevantNotes)]]
            ]
        ]

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent") else {
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
