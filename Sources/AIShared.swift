import Foundation

/// A parsed AI response: what to say back, and optionally an action to perform on the notes.
struct AIActionResponse {
    var reply: String
    var action: String   // "none" | "create_note" | "update_note" | "delete_note"
    var target: String?  // text identifying an existing note, for update/delete
    var title: String?   // title for a new note
    var content: String? // full body text for a new note, or the full new body for an update
    var segments: [AISegment] = [] // reply broken into pieces tagged by source note, for "none" answers
    var categoryEnglish: String? = nil // suggested category in English, for create/update (online AI only)
    var categoryKurdish: String? = nil // the same category in Kurdish, for create/update (online AI only)
}

/// One piece of a "none"-action reply, optionally tied to the note it came from.
struct AISegment: Equatable {
    var text: String
    var sourceNote: String?    // title of the note this piece of text came from, if any
    var sourceExcerpt: String? // the exact original line/phrase in that note, for jump-to-highlight
    var isValue: Bool = false  // true if this piece is a clean, directly copyable value (password, code, price, etc.)
}

/// One turn of prior conversation, for multi-turn follow-up context. role must be "user" or "model".
struct ConversationTurn {
    let role: String
    let text: String
}

/// Shared prompt + parsing logic used by both LocalAI and OnlineAI, so both engines
/// speak the same "protocol" and AskView only has to handle one response shape.
enum AIProtocol {
    static func systemPrompt(notes: [Note], notePattern: String? = nil, includeCategoryTagging: Bool = false) -> String {
        let context = notes.map { note -> String in
            let title = note.title.isEmpty ? "Untitled" : note.title
            return "Title: \(title)\nBody: \(note.body)"
        }.joined(separator: "\n\n")

        let patternSection: String
        if let notePattern, !notePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patternSection = "\n\nWhen creating a new note (create_note), follow this pattern/style the user prefers for their notes:\n\(notePattern)"
        } else {
            patternSection = ""
        }

        let categoryFieldsJSON = includeCategoryTagging ? ", \"category_en\": \"\", \"category_ku\": \"\"" : ""

        let categorySection: String
        if includeCategoryTagging {
            categorySection = "\n\nWhen the action is \"create_note\" or \"update_note\", also suggest a short category for the note (e.g. Finance, Health, Passwords, Work) in TWO languages: put the English category in \"category_en\", and the same category translated into Kurdish (Central Kurdish / Sorani, written in Kurdish Arabic-based script) in \"category_ku\". Keep both short — a word or two. For any other action, or if you don't have a confident category, leave both fields empty."
        } else {
            categorySection = ""
        }

        return """
        You are an assistant inside a personal notes app. You can answer questions about the notes below, and you can also make changes to the notes when asked.

        Relevant notes:
        \(context.isEmpty ? "(no matching notes found)" : context)\(patternSection)

        Always respond with ONLY a single JSON object and nothing else — no explanation, no markdown code fences — matching exactly this shape:
        {"reply": "short message to show the user", "action": "none", "target": "", "title": "", "content": "", "segments": []\(categoryFieldsJSON)}

        Rules:
        - "action" must be exactly one of: "none", "create_note", "update_note", "delete_note".
        - Use "none" when the user is just asking a question. Put your answer in "reply", using ONLY the notes above. If the notes don't answer it, say so in "reply".
        - Use "create_note" when the user asks to add/create a new note. Put a short title in "title" and the note text in "content".
        - Use "update_note" when the user asks to change, edit, or correct something in an existing note (like a price). Put text identifying which note in "target" (e.g. words from its title), and put the ENTIRE new note body in "content" — the complete original text with the requested change applied, not just the changed part.
        - Use "delete_note" when the user asks to delete or remove a note. Put text identifying which note in "target".
        - If you'd use update_note or delete_note but no note above clearly matches, use "none" instead and explain in "reply" that you couldn't find that note.
        - "reply" must always be filled in with a short, friendly confirmation of what you did, or your answer to the question.
        - You may also be given earlier turns of this conversation. Use them to understand follow-up questions (e.g. "what about that one" or "make it 25 instead"), but the rules above still apply to every response.

        For "segments" (ONLY when action is "none"): break your "reply" text into an ordered list of pieces that, joined together, reconstruct "reply" as closely as possible. Each piece is an object: {"text": "the piece of the reply", "source_note": "exact title of the note this piece is based on, or empty if it's not tied to a specific note (like a greeting or connecting words)", "source_excerpt": "the exact original line or phrase from that note that supports this piece, copied verbatim, or empty if source_note is empty", "is_value": false}. This applies to EVERY kind of fact pulled from a note — including things like passwords, emails, phone numbers, dates, and other personal details, not just "interesting" facts. If your reply draws on multiple notes, give each fact its own segment tagged with its own note. Do this consistently and every time a reply uses note content — never skip it. If the reply doesn't draw on any note content (or the action isn't "none"), just use an empty array for "segments".

        Set "is_value" to true ONLY on the one piece that is the exact, clean, directly-copyable answer itself — a password, code, price, phone number, date, etc. — with none of the surrounding sentence. For example, if asked for a password and the note says the password is example292#, you might reply "The password for example@gmail.com is example292#." with segments: {"text": "The password for example@gmail.com is ", "is_value": false}, {"text": "example292#", "source_note": "...", "source_excerpt": "...", "is_value": true}, {"text": ".", "is_value": false}. Most segments should have "is_value": false — only use true for a short, clean, single value, never for a full sentence or phrase.\(categorySection)
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

        let segments: [AISegment] = (obj["segments"] as? [[String: Any]])?.compactMap { entry in
            guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
            let sourceNote = (entry["source_note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let sourceExcerpt = (entry["source_excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let isValue = (entry["is_value"] as? Bool) ?? false
            return AISegment(text: text, sourceNote: sourceNote, sourceExcerpt: sourceExcerpt, isValue: isValue)
        } ?? []

        return AIActionResponse(
            reply: reply,
            action: (obj["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none",
            target: nonEmpty("target"),
            title: nonEmpty("title"),
            content: nonEmpty("content"),
            segments: segments,
            categoryEnglish: nonEmpty("category_en"),
            categoryKurdish: nonEmpty("category_ku")
        )
    }
}
