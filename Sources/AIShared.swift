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
        ("read_notes", "read the full text of any notes it needs before answering"),
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

        // Ordered most specific first. The day/month forms are here because the app's own example
        // note is written "10/10/2025", and a model copying that shape used to have its reminder
        // refused with "I couldn't read that date" - the note was created and the reminder silently
        // wasn't. Day-first is tried before month-first, which is how the region writes it.
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
            "d-M-yyyy H:mm",
            "d-M-yyyy",
            "d/M/yyyy H:mm",
            "d/M/yyyy",
            "M/d/yyyy H:mm",
            "M/d/yyyy",
            "d MMMM yyyy HH:mm",
            "d MMMM yyyy",
            "MMMM d, yyyy",
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
    /// - Parameter relevantIDs: the notes the question's own words point at. Everything is listed,
    ///   because "how many notes do I have" and "list my overdue ones" need the whole set, but the
    ///   bodies of notes that look relevant are given in full and the rest are given a short excerpt.
    ///   Previously every body was sent whole on every turn, which is what made a big collection slow
    ///   and, past the ceiling, silently truncated.
    static func systemPrompt(notes: [Note],
                            notePattern: String? = nil,
                            includeCategoryTagging: Bool = false,
                            includeReminderTagging: Bool = false,
                            notesAreComplete: Bool = false,
                            contextBudget: Int = 16_000,
                            relevantIDs: Set<UUID> = []) -> String {
        /// Chars of body each note may spend. Priority notes keep their text; the rest are indexed
        /// so the model can still find them by title and category.
        let priorityBodyLimit = 4_000
        let otherBodyLimit = 240

        /// The sentence a shortened note carries. It is a *constant* rather than a literal inside
        /// `clipped` because the budget maths has to subtract it: a slice that comes with a warning
        /// attached costs more than its allowance, and across three hundred notes that overage is what
        /// tips a request over the ceiling.
        let clipWarning = "\n…(the rest of this note was left out to keep the request small)"
        func clipped(_ text: String, _ limit: Int) -> String {
            guard text.count > limit else { return text }
            return String(text.prefix(limit)) + clipWarning
        }

        // Which notes deserve the room: the ones the question's own words point at, then everything
        // else in the list's own order.
        let relevant = relevantIDs.isEmpty ? [] : notes.filter { relevantIDs.contains($0.id) }
        let ordered = relevant + notes.filter { !relevantIDs.contains($0.id) }

        func title(of note: Note) -> String { note.title.isEmpty ? "Untitled" : note.title }

        /// One note, described at one of three levels of detail: everything; then bodies only for the
        /// notes that look relevant, with all their metadata; then a title and category each, sized so
        /// that every note in the collection gets one. The levels
        /// exist because the service counts tokens for the *whole* request per minute, so the only way
        /// to keep working for somebody with four hundred notes is to give up detail in a chosen order -
        /// the bodies of notes nobody asked about first - instead of sending a request that gets
        /// refused. A question that points at nothing treats every note as a candidate.
        func describe(_ note: Note, bodyLimit: Int, withDetails: Bool) -> String {
            var parts = ["Title: \(title(of: note))"]
            if withDetails, !note.categoryEnglish.isEmpty {
                parts.append("Category: \(note.categoryEnglish)\(note.categoryKurdish.isEmpty ? "" : " / \(note.categoryKurdish)")")
            }
            if withDetails, let reminder = note.reminderDate {
                parts.append("Reminder: \(reminderDateFormatter.string(from: reminder)) (\(note.isReminderCompleted ? "done" : "open"))")
            }
            if withDetails {
                parts.append("Created: \(dayFormatter.string(from: note.dateCreated)), edited: \(dayFormatter.string(from: note.dateModified))")
            } else if !note.categoryEnglish.isEmpty {
                // Even the meanest line says what the note is about, so "which ones are Work" stays
                // answerable when nothing else can be afforded.
                parts[0] = "Title: \(title(of: note)) (\(note.categoryEnglish))"
            }
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if bodyLimit > 0, !body.isEmpty { parts.append("Body: \(clipped(body, bodyLimit))") }
            return parts.joined(separator: "\n")
        }

        // What one line costs before any of its body is added, at the compact level. Subtracting the
        // real total rather than guessing at a fixed overhead is what keeps the budget *used*: a
        // hundred and twenty notes otherwise lands on "titles only" with fourteen thousand characters
        // of room left unspent, which reads to the user as the assistant having forgotten everything.
        let compactFraming = ordered.reduce(0) { $0 + describe($1, bodyLimit: 0, withDetails: false).count + 2 }
        let sharedBodyLimit = max(0, (contextBudget - compactFraming) / max(ordered.count, 1) - clipWarning.count)

        func describe(_ note: Note, level: Int) -> String {
            let priority = relevantIDs.isEmpty || relevantIDs.contains(note.id)
            switch level {
            case 0: return describe(note, bodyLimit: priority ? (relevantIDs.isEmpty ? Int.max : priorityBodyLimit) : otherBodyLimit, withDetails: true)
            case 1: return describe(note, bodyLimit: priority ? priorityBodyLimit : 0, withDetails: true)
            default: return describe(note, bodyLimit: priority ? sharedBodyLimit : 0, withDetails: false)
            }
        }

        func listing(_ level: Int) -> [String] {
            ordered.map { describe($0, level: level) }
        }

        var entries = listing(0)
        var context = entries.joined(separator: "\n\n")
        var truncationNotice = ""
        if !relevantIDs.isEmpty,
           ordered.contains(where: { !relevantIDs.contains($0.id) && $0.body.count > otherBodyLimit }) {
            truncationNotice = "\n\nNote: every note is listed, but the ones that don't look relevant to this question are shown as an excerpt. If the answer might be in a part you were not given, say that instead of saying it is not there."
        }
        var level = 0
        while context.count > contextBudget && level < 2 {
            level += 1
            entries = listing(level)
            context = entries.joined(separator: "\n\n")
            // Two different truths, depending on whether anything was prioritised: with a focused
            // question the far notes lose their bodies, and with one that pointed at nothing every note
            // keeps a slice of its own. Saying the first about the second would make the model think it
            // was given a subset, when it was given all of them briefly.
            truncationNotice = relevantIDs.isEmpty
                ? "\n\nNote: \(notes.count) notes exist and all of them are listed here; their bodies are shortened as much as the size the service allows requires, and some may carry no body at all. If the answer might be in a part you were not given, say that instead of saying it is not there, and use the list or search tool to look again."
                : "\n\nNote: \(notes.count) notes exist. To keep this request within the size the service allows, bodies are shown only for the notes that look relevant; the rest are listed by title. If the answer might be in a note you were not given, say that instead of saying it is not there."
        }
        // Last resort: fewer notes rather than a request that is refused outright. Cutting the list is
        // also what makes "these are ALL your notes" untrue, so that claim is tied to this flag and
        // cannot survive the cut - a model told the list is complete answers "that isn't in your notes"
        // about something it was never shown, which is the worst possible way to be wrong here.
        var omitted = 0
        if context.count > contextBudget {
            var kept: [String] = []
            var used = 0
            // Whole notes only, and counted in notes: the split cannot be done on the finished text,
            // because a note with a blank line in it *is* two pieces of text and would then be
            // reported as two notes and cut in half.
            for entry in entries {
                if used + entry.count + 2 > contextBudget, !kept.isEmpty { break }
                kept.append(entry)
                used += entry.count + 2
            }
            omitted = ordered.count - kept.count
            context = kept.joined(separator: "\n\n")
            truncationNotice = "\n\nNote: \(notes.count) notes exist and only \(kept.count) are shown here, because the whole list would not fit in one request. Do not say something is missing from the collection; say you were shown part of it. For a count or a list, use list_notes or search_notes, which the app answers from the device."
        }
        let listingIsComplete = omitted == 0

        let notesHeader = (notesAreComplete && listingIsComplete)
            ? "Here are ALL of the user's notes, every single one, with their categories, reminders and dates. Read every note before saying something is missing - do not skim, and do not assume. If the answer is anywhere in here, state it confidently."
            : "Notes that look relevant (there may be others):"

        // What to do about a listing the model cannot fully read. Without this paragraph the honest
        // answer to any question needing a body is a guess from a title, which is how the assistant
        // came to look like it had forgotten its own notebook: the excerpt was the whole of what it was
        // given, and nothing told it that more was reachable.
        let readSection = """


        This listing is an index, not the notebook. A note whose body is shortened or missing is still
        there and still readable: answer with "action": "read_notes" and the app replies with the real
        text, then you answer. Name the notes you want in "targets" (titles, or any words that identify
        them) or a whole set in "content": all, overdue, upcoming, done, untagged, category:Name,
        search:words. Ask for several notes in one call instead of one note at a time. Never state what a
        note says from its title alone, and never say something is not in the notes because the listing
        did not show it - read it first. The app grants a few lookups per question and tells you when it
        will not grant another. search_notes and list_notes are different: those change what the user
        sees on screen, so use them only when the user asked to see or count something.

        If the user asks you to go through everything - summarise the notebook, check every note for a
        mistake, find all the ones about X - do not answer from the listing alone. Ask for content "all"
        or the set named in the question, read what comes back, and ask again for the rest until you have
        covered them; a few notes at a time is fine and expected. Say which ones you reached if you run
        out of lookups.
        """

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
        You are the assistant inside a personal notes app on this phone. You are not working from a
        quotation: the notebook itself is behind the listing below, you can read any part of it, and you
        can change it - through the actions listed here, which are the whole of what you can do, so
        never offer anything else. Use them, including the reads, instead of guessing from a title or an
        excerpt, and prefer looking something up over saying you cannot.

        \(notesHeader)
        \(context.isEmpty ? "(no notes yet)" : context)\(readSection)\(patternSection)\(truncationNotice)

        Reply with ONLY one JSON object and nothing else - no prose, no markdown fences - in exactly
        this shape:
        {"reply": "", "action": "none", "target": "", "title": "", "content": "", "find": "", "replace": "", "targets": [], "scope": "", "segments": []\(categoryFieldsJSON)\(reminderFieldsJSON)}

        "action" must be exactly one of: \(actionList).

        - none — an answer to a question. Put it in "reply", using ONLY the notes you have read. If
          they do not answer it, read more of them, and only then say so plainly; do not guess.
        - read_notes — text you were not given. "targets" and/or "content" as described above. The app
          answers you with the note text and lets you ask again; nothing the user sees moves.
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
        var names = ["none", "read_notes", "create_note", "patch_note", "append_to_note", "update_note",
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
        // Balanced-brace scan rather than first-brace-to-last-brace, so a stray "{" in a note title
        // or a second object can't stretch the slice.
        func scan(from start: String.Index) -> (slice: Substring, next: String.Index)? {
            var depth = 0
            var inString = false
            var escaped = false
            var index = start
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
                        if depth == 0 { return (text[start...index], text.index(after: index)) }
                    }
                }
                index = text.index(after: index)
            }
            return nil
        }

        // Every object the reply contains, in order. A chat model is asked for exactly one, and
        // usually obeys; the models that don't are the reasoning kind, which preface the answer with a
        // sentence about the schema ("respond with {action, reply}") or restate it afterwards. Taking
        // the first object then means reading the model's own note about the format as the answer.
        var found: [[String: Any]] = []
        var cursor = text.startIndex
        while let open = text[cursor...].firstIndex(of: "{"), let scanned = scan(from: open) {
            if let data = String(scanned.slice).data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                found.append(object)
            }
            cursor = scanned.next
        }
        guard !found.isEmpty else { return nil }
        // Prefer the last one that looks like an answer rather than an example: the protocol's own keys
        // (or a category pair, for the note-tagging call). If none of them claim to be an answer, the
        // last is the better guess than the first, because a rambling model puts the real thing last.
        let isAnswer = ["action", "reply", "category_en"]
        return found.last { object in object.keys.contains(where: { isAnswer.contains($0) }) } ?? found.last
    }

    /// Answers a `read_notes` request out of a snapshot of the notes. Deliberately a plain function
    /// over `[Note]` rather than part of `AIActions`: this exchange happens between the model and the
    /// notebook, and nothing on screen moves because of it - no tab change, no search box, no filter.
    /// The text is clipped to `budget` so that a lookup cannot become a way to smuggle an oversized
    /// request through in three pieces, and it never returns an empty string: an empty turn would be
    /// resent as a question with nothing new in it, which is a round wasted and an answer no better.
    static func lookupText(for parsed: AIActionResponse, in notes: [Note], budget: Int) -> String {
        func titleOf(_ note: Note) -> String { note.title.isEmpty ? "Untitled" : note.title }

        guard !notes.isEmpty else {
            return "You have no notes at all, so there is nothing to read. Say that, and offer to make one."
        }

        // Named notes first and in the order asked, so "the deposit one, then the rent one" reads the
        // way the question was put.
        var picked: [Note] = []
        var misses: [String] = []
        for raw in parsed.targets + [parsed.target ?? ""] {
            let want = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !want.isEmpty else { continue }
            if let match = QuestionAnswerer.bestMatchingNote(for: want, in: notes),
               !picked.contains(where: { $0.id == match.id }) {
                picked.append(match)
            } else if !misses.contains(want) {
                misses.append(want)
            }
        }

        // A set, when the question was about a group rather than a note.
        var scope = (parsed.content ?? parsed.scope ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Models put a verb in front of the name of a set half the time ("read all", "show overdue"),
        // and left that way it reads as a description of a single note, so the words "read" and "notes"
        // get matched against everything and the answer comes back about the wrong note.
        for filler in ["read the notes: ", "read notes: ", "read ", "show ", "list ", "notes about ", "about "] {
            if scope.hasPrefix(filler) { scope = String(scope.dropFirst(filler.count)); break }
        }
        scope = scope.trimmingCharacters(in: .whitespaces)
        if picked.isEmpty, !scope.isEmpty {
            let set: [Note]
            switch scope {
            case "all", "every", "everything", "notes", "all notes":
                set = notes
            case "overdue":
                set = notes.filter { ($0.reminderDate ?? .distantFuture) < Date() && !$0.isReminderCompleted }
            case "upcoming", "reminders":
                set = notes.filter { $0.reminderDate != nil && !$0.isReminderCompleted }
            case "done", "completed":
                set = notes.filter { $0.isReminderCompleted }
            case "untagged", "uncategorized":
                set = notes.filter { $0.categoryEnglish.isEmpty }
            default:
                let name: (String) -> String = { String(scope.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) }
                if scope.hasPrefix("category:"), scope.count > 9 {
                    let wanted = name("category:")
                    set = notes.filter { $0.categoryEnglish.caseInsensitiveCompare(wanted) == .orderedSame }
                } else if scope.hasPrefix("search:"), scope.count > 7 {
                    let words = name("search:")
                    set = notes.filter {
                        $0.title.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                            || $0.body.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                } else {
                    // Anything else is a description of a note rather than a set, so it is treated as
                    // one more way to point: the same matcher the mutating actions use, so "the note
                    // about the landlord" finds the note here as reliably as it does for patch_note.
                    set = QuestionAnswerer.topMatchingNotes(for: scope, in: notes, limit: 12)
                }
            }
            for note in set where !picked.contains(where: { $0.id == note.id }) { picked.append(note) }
        }

        // A miss is answered with the titles, because "I couldn't find it" leaves the model to invent a
        // name, while the list lets it pick the right one on the next round.
        guard !picked.isEmpty else {
            let what = misses.isEmpty ? "any note from that description" : misses.joined(separator: ", ")
            let titles = notes.prefix(40).map { titleOf($0) }.joined(separator: ", ")
            let tail = notes.count > 40 ? ", and \(notes.count - 40) more" : ""
            return "Nothing matches \(what). Your notes are titled: \(titles)\(tail). Ask for one of those."
        }

        // Room is kept back for the sentence saying the rest did not fit, so the promise that a lookup
        // stays inside its budget survives the very moment it has to be broken - otherwise the notice
        // that reports the clipping is itself what pushes the request over.
        let roomToSpare = min(max(0, budget - 160), 96)
        var out = ""
        var shown = 0
        for note in picked {
            let room = budget - roomToSpare - out.count
            // The `out.isEmpty` test is what keeps a small budget from returning *nothing*: an empty
            // answer turn is resent as a question with no new text in it, which wastes a round and
            // teaches the model that reading the notes achieves nothing.
            guard room > 160 || out.isEmpty else {
                out += "\n\n(\(picked.count - shown) more notes were left out of this reply for size - ask again for them)"
                break
            }
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = "\(titleOf(note)) [\(note.categoryEnglish.isEmpty ? "no category" : note.categoryEnglish)]: \(body.isEmpty ? "(no text in this note)" : body)"
            // The marker is subtracted as well as added: a slice of exactly `room` characters plus the
            // sentence saying it was cut is one sentence longer than the budget allowed.
            let cutMark = "…(cut off by the size limit)"
            if record.count > room { record = String(record.prefix(max(0, room - cutMark.count))) + cutMark }
            out += (out.isEmpty ? "" : "\n\n") + record
            shown += 1
        }
        return out
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
        case "", "none", "answer", "respond", "reply": return "none"
        case "fetch_notes", "get_notes", "read_note", "read_all_notes", "load_notes": return "read_notes"
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
