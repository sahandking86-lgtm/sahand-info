import Foundation

/// A parsed AI response: what to say back, and optionally an action to perform on the notes.
struct AIActionResponse {
    var reply: String
    var action: String   // "none" | "create_note" | "update_note" | "delete_note"
    var target: String?  // text identifying an existing note, for update/delete
    var title: String?   // title for a new note
    var content: String? // full body text for a new note, or the full new body for an update
}

/// Shared prompt + parsing logic used by both LocalAI and OnlineAI, so both engines
/// speak the same "protocol" and AskView only has to handle one response shape.
enum AIProtocol {
    static func systemPrompt(notes: [Note]) -> String {
        let context = notes.map { note -> String in
            let title = note.title.isEmpty ? "Untitled" : note.title
            return "Title: \(title)\nBody: \(note.body)"
        }.joined(separator: "\n\n")

        return """
        You are an assistant inside a personal notes app. You can answer questions about the notes below, and you can also make changes to the notes when asked.

        Relevant notes:
        \(context.isEmpty ? "(no matching notes found)" : context)

        Always respond with ONLY a single JSON object and nothing else — no explanation, no markdown code fences — matching exactly this shape:
        {"reply": "short message to show the user", "action": "none", "target": "", "title": "", "content": ""}

        Rules:
        - "action" must be exactly one of: "none", "create_note", "update_note", "delete_note".
        - Use "none" when the user is just asking a question. Put your answer in "reply", using ONLY the notes above. If the notes don't answer it, say so in "reply".
        - Use "create_note" when the user asks to add/create a new note. Put a short title in "title" and the note text in "content".
        - Use "update_note" when the user asks to change, edit, or correct something in an existing note (like a price). Put text identifying which note in "target" (e.g. words from its title), and put the ENTIRE new note body in "content" — the complete original text with the requested change applied, not just the changed part.
        - Use "delete_note" when the user asks to delete or remove a note. Put text identifying which note in "target".
        - If you'd use update_note or delete_note but no note above clearly matches, use "none" instead and explain in "reply" that you couldn't find that note.
        - "reply" must always be filled in with a short, friendly confirmation of what you did, or your answer to the question.
        """
    }

    static func parse(_ raw: String) -> AIActionResponse {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard
            let firstBrace = text.firstIndex(of: "{"),
            let lastBrace = text.lastIndex(of: "}"),
            firstBrace < lastBrace
        else {
            return AIActionResponse(reply: text.isEmpty ? "Done." : text, action: "none", target: nil, title: nil, content: nil)
        }

        let jsonSubstring = text[firstBrace...lastBrace]

        guard
            let data = jsonSubstring.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return AIActionResponse(reply: text, action: "none", target: nil, title: nil, content: nil)
        }

        let rawReply = (obj["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = (rawReply?.isEmpty ?? true) ? "Done." : rawReply!

        func nonEmpty(_ key: String) -> String? {
            (obj[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        return AIActionResponse(
            reply: reply,
            action: obj["action"] as? String ?? "none",
            target: nonEmpty("target"),
            title: nonEmpty("title"),
            content: nonEmpty("content")
        )
    }
}
