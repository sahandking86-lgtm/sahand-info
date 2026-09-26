//
//  AIActions.swift
//
//  Everything the assistant is allowed to actually do, in one place.
//
//  Two rules run through this file:
//
//  1. A change that cannot be described in the reply is a bug. Every branch returns what happened,
//     which the chat then records, so the model's own memory matches the notes ("it kept saying I
//     had no note about the thing it had just created" was caused by the reply text being the only
//     thing remembered).
//  2. If something cannot be done, it says so in plain words and offers what it can do instead.
//     Before this, an unrecognised action fell through to a default branch that quietly rendered
//     the reply as an answer - so "delete all my notes" looked handled and did nothing.
//

import SwiftUI

@MainActor
enum AIActions {
    struct Result {
        var reply: String
        /// Notes to flash in the list, so a change made while looking at another tab is findable.
        var changed: [UUID] = []
        /// A note the reply offers to open (the card under the bubble).
        var openableID: UUID?
        var openableTitle: String?
        /// Set when the change needs a tap - or a typed "yes" - before it happens.
        var confirmation: PendingConfirmation?
        /// True when the reply is a refusal or a problem, so the chat can style and remember it as one.
        var isFailure = false
        /// What to append to the conversation so the model knows the real outcome next turn.
        var outcomeForHistory: String?
    }

    // MARK: - Entry point

    static func apply(_ parsed: AIActionResponse,
                      question: String,
                      in store: NotesStore,
                      settings: SettingsStore,
                      coordinator: AppCoordinator) -> Result {
        var result = Result(reply: parsed.reply)
        let notes = store.notes

        switch parsed.action {
        case "none", "":
            result.reply = parsed.reply
            // If the answer came from exactly one note, offer the card the Settings text promises
            // ("a short written answer plus a tappable note card") instead of leaving it unused.
            let titles = Set(parsed.segments.compactMap { $0.sourceNote })
            if titles.count == 1, let title = titles.first,
               let match = QuestionAnswerer.bestMatchingNote(for: title, in: notes) {
                result.openableID = match.id
                result.openableTitle = match.title.isEmpty ? "Untitled" : match.title
            }
            return result

        case "create_note":
            var note = Note(title: parsed.title ?? "", body: parsed.content ?? "")
            note.categoryEnglish = parsed.categoryEnglish ?? ""
            note.categoryKurdish = parsed.categoryKurdish ?? ""
            if let raw = parsed.reminderDate {
                if let date = AIProtocol.reminderDate(from: raw) {
                    note.reminderDate = date
                } else {
                    result.reply += " (I couldn't read the reminder time, so the note was created without one — tell me the date in yyyy-MM-dd HH:mm form and I'll add it.)"
                }
            }
            store.add(note, label: "Added “\(note.title.isEmpty ? "Untitled" : note.title)”")
            result.changed = [note.id]
            result.openableID = note.id
            result.openableTitle = note.title.isEmpty ? "Untitled" : note.title
            coordinator.say("Saved “\(result.openableTitle ?? "Untitled")”.", actionLabel: "Show", noteID: note.id)
            result.outcomeForHistory = "[done] created note \"\(result.openableTitle ?? "Untitled")\""
                + (note.categoryEnglish.isEmpty ? "" : " in category \(note.categoryEnglish)")
                + (note.reminderDate == nil ? "" : " with a reminder")
            return result

        case "update_note":
            guard let target = parsed.target, !target.isEmpty else {
                return refused(parsed, "Say which note you mean and I'll change it.", store: store)
            }
            guard let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "change that note", store: store)
            }
            let newBody = parsed.content ?? match.body
            // A rewrite is the one operation that can lose text. If the proposed body is much
            // shorter than the original, do not apply it silently - show what it would become.
            if newBody != match.body, newBody.count * 2 < match.body.count, !match.body.isEmpty {
                result.confirmation = PendingConfirmation(
                    question: "Rewrite “\(title(of: match))” completely?",
                    detail: "The new text is \(newBody.count) characters and the note is \(match.body.count). I only do this on your say-so, because the rest of the note would be gone.",
                    noteIDs: [match.id],
                    noteTitles: [title(of: match)],
                    isDestructive: true
                )
                result.reply = "That would replace the whole note. Check the card below first — or ask me to change just the part you mean."
                result.outcomeForHistory = "[waiting] asked the user to confirm a full rewrite of \"\(title(of: match))\""
                return result
            }
            var updated = match
            updated.body = newBody
            if let title = parsed.title, !title.isEmpty { updated.title = title }
            if let en = parsed.categoryEnglish, !en.isEmpty { updated.categoryEnglish = en }
            if let ku = parsed.categoryKurdish, !ku.isEmpty { updated.categoryKurdish = ku }
            updated.dateModified = Date()
            store.update(updated, label: "Updated “\(title(of: match))”")
            result.changed = [match.id]
            result.openableID = match.id
            result.openableTitle = title(of: updated)
            coordinator.markChanged([match.id])
            result.outcomeForHistory = "[done] rewrote \"\(title(of: match))\""
            return result

        case "patch_note":
            guard let target = parsed.target, let find = parsed.find, !find.isEmpty,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "change that note", store: store)
            }
            let replacement = parsed.replace ?? ""
            guard let range = match.body.range(of: find, options: [.caseInsensitive]) else {
                result.reply = "I looked in “\(title(of: match))” for “\(find)” and it isn't there, so I changed nothing. Tell me the words as they appear in the note and I'll fix it."
                result.isFailure = true
                result.outcomeForHistory = "[failed] the text to change (\"\(find)\") was not found in \"\(title(of: match))\"; no change made"
                return result
            }
            var updated = match
            updated.body = match.body.replacingCharacters(in: range, with: replacement)
            if let newTitle = parsed.title, !newTitle.isEmpty { updated.title = newTitle }
            updated.dateModified = Date()
            store.update(updated, label: "Edited “\(title(of: match))”")
            result.changed = [match.id]
            result.openableID = match.id
            result.openableTitle = title(of: updated)
            coordinator.markChanged([match.id])
            result.outcomeForHistory = "[done] changed \"\(find)\" to \"\(replacement)\" inside \"\(title(of: match))\" — the rest of the note is untouched"
            return result

        case "append_to_note":
            guard let target = parsed.target,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "add to that note", store: store)
            }
            let line = (parsed.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                result.reply = "Tell me what to add and I'll put it in \(title(of: match))."
                result.isFailure = true
                return result
            }
            var updated = match
            updated.body = updated.body.isEmpty ? line : updated.body + "\n" + line
            updated.dateModified = Date()
            store.update(updated, label: "Added a line to “\(title(of: match))”")
            result.changed = [match.id]
            result.openableID = match.id
            result.openableTitle = title(of: updated)
            coordinator.markChanged([match.id])
            result.outcomeForHistory = "[done] appended to \"\(title(of: match))\""
            return result

        case "delete_note", "delete_notes", "delete_all_notes":
            return deletion(parsed: parsed, action: parsed.action, notes: notes,
                            store: store, coordinator: coordinator, into: &result)

        case "set_reminder":
            guard let target = parsed.target,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "set that reminder", store: store)
            }
            var updated = match
            var setSomething = false
            if let raw = parsed.reminderDate {
                if let date = AIProtocol.reminderDate(from: raw) {
                    updated.reminderDate = date
                    updated.isReminderCompleted = false
                    setSomething = true
                } else {
                    result.reply += " (I couldn't read that date, so the reminder time is unchanged — try yyyy-MM-dd HH:mm.)"
                }
            }
            if let done = parsed.reminderDone {
                updated.isReminderCompleted = done
                setSomething = true
            }
            guard setSomething else {
                result.reply = "Tell me when to remind you — for example “tomorrow at 9” or “on 12 May”."
                result.isFailure = true
                return result
            }
            updated.dateModified = match.dateModified
            store.update(updated, label: "Reminder on “\(title(of: match))”")
            result.changed = [match.id]
            result.openableID = match.id
            coordinator.markChanged([match.id])
            result.outcomeForHistory = "[done] reminder set on \"\(title(of: match))\""
            return result

        case "remove_reminder":
            guard let target = parsed.target,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "remove that reminder", store: store)
            }
            guard match.reminderDate != nil || match.isReminderCompleted else {
                result.reply = "\(title(of: match)) has no reminder to remove."
                return result
            }
            var updated = match
            updated.reminderDate = nil
            updated.isReminderCompleted = false
            updated.dateModified = match.dateModified
            store.update(updated, label: "Removed reminder on “\(title(of: match))”")
            result.changed = [match.id]
            coordinator.markChanged([match.id])
            result.outcomeForHistory = "[done] removed the reminder from \"\(title(of: match))\""
            return result

        case "set_category":
            guard let target = parsed.target,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "categorise that note", store: store)
            }
            var updated = match
            let en = (parsed.categoryEnglish ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            updated.categoryEnglish = en
            updated.categoryKurdish = (parsed.categoryKurdish ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if en.isEmpty { updated.categoryKurdish = "" }
            updated.dateModified = Date()
            store.update(updated, label: en.isEmpty ? "Cleared category on “\(title(of: match))”" : "Categorised “\(title(of: match))” as \(en)")
            result.changed = [match.id]
            coordinator.markChanged([match.id])
            // A newly named category can create a chip the user cannot see without scrolling to the
            // end of the chips row; say what happened instead of leaving the row to grow silently.
            if !en.isEmpty {
                coordinator.say("“\(title(of: match))” is now in \(en).", actionLabel: "Show", noteID: match.id)
            }
            result.outcomeForHistory = "[done] category of \"\(title(of: match))\" is now \"\(en.isEmpty ? "(none)" : en)\""
            return result

        case "search_notes":
            let query = (parsed.target ?? parsed.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                result.reply = "What should I search for?"
                result.isFailure = true
                return result
            }
            coordinator.categoryFilter = nil
            coordinator.searchText = query
            coordinator.selectedTab = .notes
            let hits = store.visibleNotes(search: query, category: nil)
            result.reply = hits.isEmpty
                ? "Nothing in your notes contains “\(query)”."
                : "\(hits.count) note\(hits.count == 1 ? "" : "s") contain “\(query)” — showing them in the Notes tab."
            result.outcomeForHistory = "[done] searched \"\(query)\", \(hits.count) notes matched"
            return result

        case "clear_search", "clear_filters":
            coordinator.clearFilters()
            result.reply = "Filters cleared — all \(store.notes.count) note\(store.notes.count == 1 ? "" : "s") are showing."
            result.outcomeForHistory = "[done] cleared search and category filters"
            return result

        case "filter_category":
            let wanted = (parsed.categoryEnglish ?? parsed.target ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else {
                coordinator.setFilter(category: nil)
                result.reply = "Showing all notes."
                return result
            }
            guard store.allCategories.contains(wanted) else {
                let known = store.allCategories
                result.reply = known.isEmpty
                    ? "You have no categories yet — once notes are tagged, “\(wanted)” becomes available."
                    : "There's no “\(wanted)” category. You have: \(known.joined(and: "and"))."
                result.isFailure = true
                return result
            }
            coordinator.setFilter(category: wanted)
            let count = store.notes.filter { $0.categoryEnglish == wanted }.count
            result.reply = "Showing \(count) note\(count == 1 ? "" : "s") in \(wanted)."
            result.outcomeForHistory = "[done] filtered the notes tab to category \"\(wanted)\""
            return result

        case "list_notes":
            let scope = (parsed.content ?? parsed.target ?? "all").lowercased()
            let list: [Note]
            switch scope {
            case "overdue": list = notes.filter { ($0.reminderDate ?? .distantFuture) < Date() && !$0.isReminderCompleted }
            case "upcoming", "reminders": list = notes.filter { $0.reminderDate != nil && !$0.isReminderCompleted }
            case "done", "completed": list = notes.filter { $0.isReminderCompleted }
            case "untagged", "uncategorized": list = notes.filter { $0.categoryEnglish.isEmpty }
            default:
                if scope.hasPrefix("category:") {
                    let name = String(scope.dropFirst("category:".count)).trimmingCharacters(in: .whitespaces)
                    list = notes.filter { $0.categoryEnglish.caseInsensitiveCompare(name) == .orderedSame }
                } else {
                    list = notes
                }
            }
            let titles = list.prefix(12).map { title(of: $0) }
            let tail = list.count > 12 ? ", and \(list.count - 12) more" : ""
            result.reply = list.isEmpty
                ? "Nothing matches that — you have \(notes.count) note\(notes.count == 1 ? "" : "s") in total."
                : "\(list.count) note\(list.count == 1 ? "" : "s"): \(titles.joined(separator: ", "))\(tail)."
            if !list.isEmpty {
                coordinator.selectedTab = .notes
                coordinator.categoryFilter = scope.hasPrefix("category:") ? String(scope.dropFirst(9)).trimmingCharacters(in: .whitespaces) : nil
            }
            result.outcomeForHistory = "[done] listed \(list.count) notes"
            return result

        case "open_note", "edit_note":
            guard let target = parsed.target,
                  let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) else {
                return notFound(parsed, action: "open that note", store: store)
            }
            let opened = coordinator.reveal(noteID: match.id,
                                            in: store,
                                            startEditing: parsed.action == "edit_note")
            guard opened else {
                result.reply = "That note isn't there any more."
                result.isFailure = true
                return result
            }
            result.reply = parsed.action == "edit_note"
                ? "Opening \(title(of: match)) in edit mode."
                : "Opened \(title(of: match))."
            result.outcomeForHistory = "[done] opened \"\(title(of: match))\""
            return result

        case "switch_tab":
            let wanted = (parsed.target ?? parsed.content ?? "").lowercased()
            switch wanted {
            case "note", "notes", "all": coordinator.selectedTab = .notes
            case "ask", "chat", "ai": coordinator.selectedTab = .ask
            case "date", "reminder", "reminders": coordinator.selectedTab = .date
            default:
                result.reply = wanted.isEmpty
                    ? "Which tab — Notes, Ask or Date?"
                    : "I can move you between the Notes, Ask and Date tabs — tell me which one."
                result.isFailure = true
                return result
            }
            result.reply = "Here you are."
            return result

        case "set_theme":
            let wanted = (parsed.target ?? parsed.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let theme = AppTheme.allCases.first(where: {
                $0.rawValue.caseInsensitiveCompare(wanted) == .orderedSame
                    || $0.displayName.caseInsensitiveCompare(wanted) == .orderedSame
            }) else {
                let names = AppTheme.allCases.map { $0.displayName }
                result.reply = "My themes are \(names.joined(and: "and")) — say one of those."
                result.isFailure = true
                return result
            }
            settings.theme = theme
            result.reply = "Now running \(theme.displayName)."
            result.outcomeForHistory = "[done] changed the theme to \"\(theme.displayName)\""
            return result

        case "set_answer_mode":
            let wanted = (parsed.target ?? parsed.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let mode: AnswerMode?
            if wanted.contains("jump") || wanted.contains("highlight") { mode = .jumpAndHighlight }
            else if wanted.contains("ai") || wanted.contains("answer") { mode = .aiAnswer }
            else { mode = nil }
            guard let mode else {
                result.reply = "Two modes: AI Answer (I write an answer and can change your notes) and Jump & Highlight (it opens the note and marks the line, no internet needed). Which one?"
                result.isFailure = true
                return result
            }
            if mode == .jumpAndHighlight && settings.answerMode != mode {
                // Saying the truth about what that mode costs, since it is the mode where the
                // assistant stops acting on requests.
                coordinator.say("Jump & Highlight answers without the assistant, so changes need AI Answer.", actionLabel: "Switch back")
            }
            settings.answerMode = mode
            result.reply = mode == .aiAnswer
                ? "AI Answer mode — I can search and change things for you here."
                : "Jump & Highlight mode — I'll open the note and mark the line, all offline."
            return result

        case "open_settings":
            coordinator.showingSettings = true
            coordinator.selectedTab = .notes
            result.reply = "Opening Settings."
            result.outcomeForHistory = "[done] opened settings"
            return result

        case "undo_last_change":
            guard store.canUndo else {
                result.reply = "There's nothing I can undo right now."
                return result
            }
            if let label = store.undoLastChange() {
                result.reply = "Undid: \(label)."
                coordinator.say("Undid: \(label)", actionLabel: nil)
                result.outcomeForHistory = "[done] undone \(label)"
            } else {
                result.reply = "I couldn't undo that one."
                result.isFailure = true
            }
            return result

        default:
            // The honest refusal. Previously any unrecognised action landed in a default branch that
            // drew the reply as a normal answer, which is how "delete all my notes" looked handled.
            result.reply = "I can't do that — there's no “\(parsed.action)” in this app. \(AIProtocol.capabilitySummary)"
            result.isFailure = true
            result.outcomeForHistory = "[refused] \"\(parsed.action)\" is not an action this app has"
            return result
        }
    }

    // MARK: - Deletion (always confirmed, always undoable afterwards)

    private static func deletion(parsed: AIActionResponse,
                                 action: String,
                                 notes: [Note],
                                 store: NotesStore,
                                 coordinator: AppCoordinator,
                                 into result: inout Result) -> Result {
        var victims: [Note] = []
        var unmatched: [String] = []
        let scope = (parsed.scope ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if action == "delete_all_notes" || scope == "all" || scope == "everything" {
            victims = notes
        } else if scope == "category", let category = parsed.categoryEnglish ?? parsed.target {
            let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
            victims = notes.filter { $0.categoryEnglish.caseInsensitiveCompare(name) == .orderedSame }
            if victims.isEmpty { unmatched = [name] }
        } else {
            let targets = parsed.targets.isEmpty ? [parsed.target ?? ""] : parsed.targets
            for target in targets where !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let match = QuestionAnswerer.bestMatchingNote(for: target, in: notes) {
                    if !victims.contains(where: { $0.id == match.id }) { victims.append(match) }
                } else {
                    unmatched.append(target)
                }
            }
        }

        guard !victims.isEmpty else {
            let which = unmatched.isEmpty ? "that" : unmatched.joined(and: "and")
            result.reply = "I couldn't find \(which) among your \(notes.count) note\(notes.count == 1 ? "" : "s"), so nothing was deleted."
            result.isFailure = true
            return result
        }

        if !unmatched.isEmpty {
            result.reply = "I found \(victims.count) of them; \(unmatched.joined(and: "and")) don't match any note."
        }

        // One note by name, or a whole category: still a tap (or a typed "yes") first. Deleting on
        // the strength of a guess was the one place the assistant could do real damage.
        result.confirmation = PendingConfirmation(
            question: victims.count == 1
                ? "Delete “\(title(of: victims[0]))”?"
                : "Delete \(victims.count) notes?",
            detail: victims.count == 1
                ? "It goes away from the Notes tab and the Date tab. You can undo from the banner straight after."
                : "\(victims.count) notes will go. Undo brings them all back.",
            noteIDs: victims.map { $0.id },
            noteTitles: victims.prefix(8).map { title(of: $0) },
            isDestructive: true
        )
        result.outcomeForHistory = "[waiting] asked to delete \(victims.count) note(s): \(victims.prefix(6).map { title(of: $0) }.joined(separator: ", "))"
        return result
    }

    /// Applies a confirmation the user approved (button or "yes"). Returns the line for the chat.
    static func confirm(_ confirmation: PendingConfirmation, in store: NotesStore, coordinator: AppCoordinator) -> String {
        let existing = Set(store.notes.map { $0.id })
        let targets = confirmation.noteIDs.filter { existing.contains($0) }
        guard !targets.isEmpty else {
            coordinator.pendingConfirmation = nil
            return "Those notes are already gone."
        }
        if confirmation.question.hasPrefix("Rewrite") {
            // The full-rewrite guard: nothing to delete, the body was already prepared by the model,
            // so here we simply say it needs re-asking through a normal update.
            coordinator.pendingConfirmation = nil
            return "Ask me again and I'll rewrite it — say what the whole note should contain."
        }
        store.delete(ids: targets, label: targets.count == 1
                     ? "Deleted a note"
                     : "Deleted \(targets.count) notes")
        coordinator.pendingConfirmation = nil
        coordinator.say("Deleted \(targets.count) note\(targets.count == 1 ? "" : "s").", actionLabel: "Undo", undoes: true)
        return "Deleted \(targets.count) note\(targets.count == 1 ? "" : "s"). The banner above can undo it."
    }

    static func decline(_ confirmation: PendingConfirmation) -> String {
        "Kept \(confirmation.noteIDs.count) note\(confirmation.noteIDs.count == 1 ? "" : "s"). Nothing was changed."
    }

    // MARK: - Small helpers

    private static func notFound(_ parsed: AIActionResponse, action: String, store: NotesStore) -> Result {
        var result = Result(reply: "")
        let count = store.notes.count
        result.reply = "I couldn't work out which note \(action) should apply to, so nothing changed. You have \(count) note\(count == 1 ? "" : "s") — use a few words from the title and I'll find it."
        result.isFailure = true
        result.outcomeForHistory = "[failed] could not identify the note for \(action); nothing changed"
        return result
    }

    private static func refused(_ parsed: AIActionResponse, _ reason: String, store: NotesStore) -> Result {
        var result = Result(reply: parsed.reply.isEmpty ? reason : "\(parsed.reply) — \(reason)")
        result.isFailure = true
        return result
    }

    private static func title(of note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
