import Foundation

enum OnlineAI {
    static func answer(question: String, relevantNotes: [Note], apiKey: String) async -> String {
        guard !apiKey.isEmpty else {
            return "Add your DeepSeek API key in Settings first."
        }

        let context = relevantNotes.map { note -> String in
            let title = note.title.isEmpty ? "Untitled" : note.title
            return "Note: \(title)\n\(note.body)"
        }.joined(separator: "\n\n")

        let systemPrompt = "You answer questions using ONLY the notes provided below. If the answer isn't in the notes, say you don't know. Be brief.\n\n\(context)"

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": question]
            ],
            "stream": false
        ]

        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            return "Invalid API URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                return "DeepSeek returned an error: \(message)"
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let content = (choices.first?["message"] as? [String: Any])?["content"] as? String
            else {
                return "Couldn't parse DeepSeek's response."
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Network error: \(error.localizedDescription)"
        }
    }
}
