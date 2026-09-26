//
//  AIShared.swift
//
//  The one protocol between the app and the model: what it may ask for, how it says so, and how the
//  app reads the answer. `AIActions` is the other half - a capability listed here must be handled
//  there, and the list below is also what Settings shows the user, so the app, the model and the
//  user are looking at the same set of possibilities. (That fixes "the assistant never says it
//  can't do something": unrecognised actions used to be rendered as a normal answer.)
//

import Foundation

/// A parsed AI response: what to say back, and optionally an action to perform on the notes.
struct AIActionResponse {
    var reply: String
    var action: String
    var target: String?      // text identifying an existing note
    var targets: [String] = []  // several notes, for bulk deletes
    var scope: String?       // "all" | "category" | "overdue" ...
    var title: String?
    var content: String?
    var find: String?        // for patch_note: the text to look for, verbatim
    var replace: String?     // for patch_note: what to put in its place
    var segments: [AISegment] = []
    var categoryEnglish: String? = nil
    var categoryKurdish: String? = nil
    var reminderDate: String? = nil
    var reminderDone: Bool? = nil
    /// True when the model's reply could not be read as the protocol at all. The chat then says so
    /// instead of printing the text as if the thing had been done.
    var malformed = false
}

/// One piece of an answer, optionally tied to the note it came from.
struct AISegment: Equatable {
    var text: String
    var sourceNote: String?
    var sourceExcerpt: String?
    var isValue: Bool = false
}

struct ConversationTurn {
    let role: String
    let text: String
}

enum AIProtocol {
    /// Every action the app can carry out, in the words the app uses for it. The prompt and the
    /// Settings screen both read this, so neither can drift from the other.
    static let capabilities: [(action: String, plainEnglish: String)] = [
        ("none", "answer a question from your notes"),
        ("create_note", "add a new note, with a category and a reminder"),
        ("patch_note", "change one piece of text inside a note, leaving the rest alone"),
        ("append_to_note", "add a line to the end of a note"),
        ("update_note", "rewrite a whole note"),
        ("delete_note", "delete one note (asks first)"),
        ("delete_notes", "delete several notes, or a whole category (asks first)"),
        ("set_reminder", "put or move a reminder on a note"),
        ("remove_reminder", "take a reminder off a note"),
        ("set_category", "give a note a category, or clear it"),
        ("search_notes", "run a search in the Notes tab"),
        ("filter_category", "show only one category"),
        ("list_notes", "count and list notes, e.g. overdue reminders"),
        ("open_note", "open a note on the Notes tab"),
        ("edit_note", "open a note already in edit mode"),
        ("switch_tab", "move you between the Notes, Ask and Date tabs"),
        ("set_theme", "change the colour theme"),
        ("set_answer_mode", "switch between AI Answer and Jump & Highlight"),
        ("open_settings", "open the Settings screen"),
        ("undo_last_change", "undo the last change to your notes"),
    ]

    static var capabilityList: [String] { capabilities.map { $0.plainEnglish } }

    static var actionNames: [String] { capabilities.map { $0.action } }

    static var capabilitySummary: String {
        "What I can do: " + capabilityList.joined(separator: ", ") + "."
    }

    /// Plain local wall-clock time, no timezone conversion in either direction.
    static var reminderDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }

    /// The single accepted format used to make "tomorrow at 9" fail for reasons nobody could see.
    /// Models drift between ISO, spaced and date-only forms, so all of them are read here, and a
    /// date with no time becomes morning rather than midnight.
    static func reminderDate(from raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "dd-MM-yyyy HH:mm",
            "dd-MM-yyyy",
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.isLenient = false
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) {
                if pattern.contains("HH") { return date }
                // Date only: nine in the morning, not midnight.
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            }
        }
        let iso = ISO8601DateFormatter()
        return iso.date(from: text)
    }

    // MARK: - Prompt

    /// - Parameter contextBudget: characters of note text the request may carry. Over the budget,
    ///   the oldest-and-least-relevant bodies are shortened and the model is *told* they were, so it
    ///   says "I only saw part of your notes" rather than confidently claiming something isn't there.
    static func systemPrompt(notes: [Note],
                            notePattern: String? = nil,
                            includeCategoryTagging: Bool = false,
                            includeReminderTagging: Bool = false,
                            notesAreComplete: Bool = false,
                            contextBudget: Int = 60_000) -> String {
        let lines = notes.map { note -> String in
            let title = note.title.isEmpty ? "Untitled" : note.title
            var parts = ["Title: \(title)"]
            // The model used to be shown only titles and bodies, so it could not answer anything
            // about categories or reminders, and could not use one to find a note.
            if !note.categoryEnglish.isEmpty {
                parts.append("Category: \(note.categoryEnglish)\(note.categoryKurdish.isEmpty ? "" : " / \(note.categoryKurdish)")")
            }
            if let reminder = note.reminderDate {
                parts.append("Reminder: \(reminderDateFormatter.string(from: reminder)) (\(note.isReminderCompleted ? "done" : "open"))")
            }
            parts.append("Created: \(dayFormatter.string(from: note.dateCreated)), edited: \(dayFormatter.string(from: note.dateModified))")
            parts.append("Body: \(note.body.isEmpty ? "(empty)" : note.body)")
            return parts.joined(separator: "\n")
        }
        var context = lines.joined(separator: "\n\n")
        var truncationNotice = ""
        if context.count > contextBudget {
            let perNote = max(400, contextBudget / max(lines.count, 1))
            context = notes.map { note -> String in
                let body = note.body
                let shown = body.count > perNote ? String(body.prefix(perNote)) + "\n…(the rest of this note was left out to keep the request small)" : body
                let title = note.title.isEmpty ? "Untitled" : note.title
                var parts = ["Title: \(title)"]
                if !note.categoryEnglish.isEmpty { parts.append("Category: \(note.categoryEnglish)") }
                if let reminder = note.reminderDate {
                    parts.append("Reminder: \(reminderDateFormatter.string(from: reminder)) (\(note.isReminderCompleted ? "done" : "open"))")
                }
                parts.append("Body: \(shown.isEmpty ? "(empty)" : shown)")
                return parts.joined(separator: "\n")
            }.joined(separator: "\n\n")
            truncationNotice = "\n\nNote: \(notes.count) notes exist and some bodies above are shortened. If the answer might be in a part you were not given, say that instead of saying it is not there."
        }

        let notesHeader = notesAreComplete
            ? "Here are ALL of the user's notes, every single one, with their categories, reminders and dates. Read every note before saying something is missing - do not skim, and do not assume. If the answer is anywhere in here, state it confidently."
            : "Notes that look relevant (there may be others):"

        let patternSection: String
        if let notePattern, !notePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patternSection = "\n\nWhen creating a new note (create_note), follow this pattern the user prefers:\n\(notePattern)"
        } else {
            patternSection = ""
        }

        let categoryFieldsJSON = includeCategoryTagging ? ", \"category_en\": \"\", \"category_ku\": \"\"" : ""
        let reminderFieldsJSON = includeReminderTagging ? ", \"reminder_date\": \"\"" : ""

        let categorySection: String
        if includeCategoryTagging {
            categorySection = "\n\nOn create_note or update_note, also suggest a short category in two languages: English in \"category_en\", the same words in Kurdish (Central Kurdish / Sorani, Arabic-based script) in \"category_ku\". One or two words, e.g. Finance, Health, Passwords, Work, Travel. To change only the category, use set_category with \"target\". An empty \"category_en\" clears it. If no note clearly matches what the user called it, use \"none\" and say so in \"reply\"."
        } else {
            categorySection = ""
        }

        let reminderSection: String
        if includeReminderTagging {
            let nowString = reminderDateFormatter.string(from: Date())
            reminderSection = "\n\nRight now is \(nowString) — local time, format yyyy-MM-dd'T'HH:mm:ss. Use that same format for \"reminder_date\" and do not convert timezones. set_reminder puts or moves a reminder on an existing note (\"target\", \"reminder_date\", and \"reminder_done\": true/false only when the user is marking it done or not done). remove_reminder takes it off. On create_note you may set \"reminder_date\" straight away. If the user's words are vague about the time, ask rather than inventing a date."
        } else {
            reminderSection = ""
        }

        let actionList = AIProtocol.actionListForPrompt(includeCategoryTagging: includeCategoryTagging,
                                                        includeReminderTagging: includeReminderTagging)

        return """
        You are the assistant inside a personal notes app on this phone. You can answer questions
        about the notes below and you can change the app's state by asking for one of the actions
        listed here — those actions are the whole of what you can do, so never offer anything else.

        \(notesHeader)
        \(context.isEmpty ? "(no notes yet)" : context)\(patternSection)\(truncationNotice)

        Reply with ONLY one JSON object and nothing else - no prose, no markdown fences - in exactly
        this shape:
        {"reply": "", "action": "none", "target": "", "title": "", "content": "", "find": "", "replace": "", "targets": [], "scope": "", "segments": []\(categoryFieldsJSON)\(reminderFieldsJSON)}

        "action" must be exactly one of: \(actionList).

        - none — an answer to a question. Put it in "reply", using ONLY the notes above. If the notes
          do not answer it, say that plainly; do not guess.
        - create_note — "title" and "content".
        - patch_note — change one piece of text inside a note. "target" finds the note, "find" is the
          words exactly as they appear in it, "replace" is what to write instead. PREFER THIS over
          update_note whenever the user asks to change, fix, correct, update or add to part of a
          note: with update_note you would have to resend the whole body, and any line you leave out
          is really deleted. Leave "content" empty when you use patch_note.
        - append_to_note — add "content" as one new line at the end of the note in "target".
        - update_note — only when the user wants the note rewritten from scratch; "content" must then
          contain every line the finished note should have.
        - delete_note — one note, "target". delete_notes — several ("targets" is a list of ways to
          recognise each) or a whole set ("scope": "all" or "category" with the category name in
          "category_en"). The app always asks the user to confirm a delete; you do not need to ask.
        - search_notes — put the words in "target" and the app runs that search in the Notes tab.
          filter_category — the category name in "category_en" (empty means show everything).
          list_notes — "content" is one of: all, overdue, upcoming, done, untagged,
          category:Name. Counting or listing is your job only through this action; never invent a
          number.
        - open_note / edit_note — "target"; the app shows that note, edit_note in edit mode.
          switch_tab — "target" is notes, ask or date. set_theme — "target" is a theme name.
          set_answer_mode — "target" is "ai" or "jump". open_settings.
          undo_last_change — puts back whatever the last change to the notes did.
        - If a note cannot be identified from what the user said, use "none" and ask which one, or
          say what you could not find. NEVER say a change was made when you returned "none".
        - If what the user asked for is not in the list above, use "none" and say you cannot do that
          in this app. Do not describe it as done, and do not offer to try.
        - "reply" is always filled: a short, plain sentence saying what you did or what you found.
          No markdown, no headings, no bullet lists - it is shown in a chat bubble.
        - You may be given earlier turns, including "[done]"/"[failed]" lines that record what
          actually happened to the notes. Trust those over your own memory of what you asked for.

        For "segments" (only when action is none): split "reply" into ordered pieces that joined
        together read like "reply". Each piece: {"text": "", "source_note": "exact title, or empty",
        "source_excerpt": "the exact words in that note that support this piece, or empty",
        "is_value": false}. Tag every fact that came from a note, including passwords, emails, phone
        numbers and dates, and give each note its own segments. Otherwise use [].

        Set "is_value" true only on the one piece that is the clean, copyable answer itself - a
        password, code, price, phone number, date - with no surrounding words. For example, asked for
        a password in a note reading "the password for example@gmail.com is example292#", reply
        "The password for example@gmail.com is example292#." with segments {"text": "The password for
        example@gmail.com is ", "is_value": false} and {"text": "example292#", "source_note": "...",
        "source_excerpt": "...", "is_value": true}. Most segments are false.\(categorySection)\(reminderSection)
        """
    }

    static func actionListForPrompt(includeCategoryTagging: Bool, includeReminderTagging: Bool) -> String {
        var names = ["none", "create_note", "patch_note", "append_to_note", "update_note",
                     "delete_note", "delete_notes", "search_notes", "filter_category", "list_notes",
                     "open_note", "edit_note", "switch_tab", "set_theme", "set_answer_mode",
                     "open_settings", "undo_last_change"]
        if includeCategoryTagging { names.append("set_category") }
        if includeReminderTagging { names.append(contentsOf: ["set_reminder", "remove_reminder"]) }
        return names.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Parsing

    /// Pulls the JSON object out of whatever the model sent. Code fences, a polite preamble, a
    /// trailing note after the object - all of it is normal for these models, and previously a
    /// reply that was 99% right but wrapped in prose was read as "no action", which looked to the
    /// user like the assistant had simply not bothered.
    static func jsonObject(in raw: String) -> [String: Any]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```objective-c", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{") else { return nil }

        // Balanced-brace scan rather than first-brace-to-last-brace, so a stray "{" in a note title
        // or a second object can't stretch the slice.
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        var end: String.Index? = nil
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { end = index; break }
                }
            }
            index = text.index(after: index)
        }
        guard let end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// Models invent names for things they have seen elsewhere. Mapping the obvious synonyms onto
    /// real actions is what turns "delete everything" into a working request instead of a shrug.
    static func normalize(action raw: String) -> String {
        let action = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch action {
        case "", "none", "answer", "respond", "reply", "read_notes": return "none"
        case "add_note", "new_note", "create", "create_a_note": return "create_note"
        case "edit_note_text", "replace_in_note", "patch", "find_replace", "change_text": return "patch_note"
        case "add_line", "append", "add_to_note": return "append_to_note"
        case "edit_note_body", "rewrite_note", "set_body": return "update_note"
        case "remove_note", "trash_note": return "delete_note"
        case "delete_all", "delete_everything", "clear_notes", "empty_notes", "delete_all_notes": return "delete_all_notes"
        case "delete_many", "delete_multiple_notes", "remove_notes": return "delete_notes"
        case "search", "find_notes", "search_notes_in_app": return "search_notes"
        case "filter", "show_category", "filter_by_category": return "filter_category"
        case "list", "count_notes", "show_notes", "list_all": return "list_notes"
        case "show_note", "go_to_note", "navigate_to_note": return "open_note"
        case "switch_to_notes", "go_to_notes", "open_tab", "switch_tab_to": return "switch_tab"
        case "set_color", "change_theme", "theme": return "set_theme"
        case "set_mode", "change_mode": return "set_answer_mode"
        case "settings", "open_app_settings": return "open_settings"
        case "undo", "revert", "undo_last": return "undo_last_change"
        case "clear_reminder", "cancel_reminder", "remove_reminder_date": return "remove_reminder"
        case "mark_done", "complete_reminder": return "set_reminder"
        case "tag_note", "categorize", "set_tags": return "set_category"
        default: return action
        }
    }

    static func parse(_ raw: String) -> AIActionResponse {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let obj = jsonObject(in: text) else {
            // Not protocol: show what came back, but never pretend a change happened.
            let cleaned = text.isEmpty ? "" : text
            return AIActionResponse(
                reply: cleaned.isEmpty ? "I couldn't make sense of that reply." : cleaned,
                action: "none",
                target: nil,
                content: nil,
                malformed: true
            )
        }

        func string(_ key: String) -> String? {
            guard let value = obj[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let rawReply = (obj["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = (rawReply?.isEmpty ?? true) ? "Done." : rawReply!

        let segments: [AISegment] = (obj["segments"] as? [[String: Any]])?.compactMap { entry in
            guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
            return AISegment(
                text: text,
                sourceNote: (entry["source_note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                sourceExcerpt: (entry["source_excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                isValue: (entry["is_value"] as? Bool) ?? false
            )
        } ?? []

        let targets = (obj["targets"] as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let scope = (obj["scope"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return AIActionResponse(
            reply: reply,
            action: normalize(action: (obj["action"] as? String) ?? "none"),
            target: string("target"),
            targets: targets,
            scope: (scope?.isEmpty ?? true) ? nil : scope,
            title: string("title"),
            content: (obj["content"] as? String),
            find: (obj["find"] as? String)?.isEmpty ?? true ? nil : obj["find"] as? String,
            replace: obj["replace"] as? String,
            segments: segments,
            categoryEnglish: string("category_en"),
            categoryKurdish: string("category_ku"),
            reminderDate: string("reminder_date") ?? string("reminder") ?? string("date"),
            reminderDone: obj["reminder_done"] as? Bool
        )
    }
}
