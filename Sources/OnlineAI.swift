import Foundation

enum OnlineAI {
    static func answer(question: String, relevantNotes: [Note], apiKey: String) async -> String {
        guard !apiKey.isEmpty else {
            return "Add your Gemini API key in Settings first."
        }

        let context = relevantNotes.map { note -> String in
            let title = note.title.isEmpty ? "Untitled" : note.title
            return "Note: \(title)\n\(note.body)"
        }.joined(separator: "\n\n")

        let systemPrompt = "You answer questions using ONLY the notes provided below. If the answer isn't in the notes, say you don't know. Be brief.\n\n\(context)"

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": question]]]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ]
        ]

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else {
            return "Invalid API URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                return "Gemini returned an error: \(message)"
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = json["candidates"] as? [[String: Any]],
                let content = candidates.first?["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]],
                let text = parts.first?["text"] as? String
            else {
                return "Couldn't parse Gemini's response."
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Network error: \(error.localizedDescription)"
        }
    }
}
