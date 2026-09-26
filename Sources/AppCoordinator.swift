//
//  AppCoordinator.swift
//
//  Which tab is open, what the Notes tab is filtered by, and which note each tab is showing - all
//  in one place instead of three `@State` properties that other tabs cannot see.
//
//  This exists because the assistant used to be unable to do half of what it said it did: it could
//  change a note, but it could not switch to the Notes tab, clear a search that was hiding the note
//  it had just added, or bring that note into view. The data was correct and the screen looked
//  empty, which reads as "it did nothing". Anything the user can do by hand now goes through here,
//  so the AI and a finger take exactly the same path.
//

import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case notes
    case ask
    case date
}

/// A note to open, plus how to open it. `highlightLine` is the specific line the answer came from,
/// which is what makes the highlight land on the right occurrence instead of the first look-alike.
struct NoteRoute: Hashable {
    let noteID: UUID
    var highlight: String? = nil
    /// The line the value was found on, so a repeated "10" cannot be picked instead of the answer.
    var highlightLine: String? = nil
    var theme: AppTheme? = nil
    var startEditing: Bool = false
}

/// A change the assistant wants confirmed before it happens. Kept here rather than inside a chat
/// bubble so that leaving the Ask tab, asking another question, or clearing the chat cannot
/// silently abandon it - and so the other tabs can say "something is waiting for you".
struct PendingConfirmation: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var detail: String
    /// The notes this touches, resolved now rather than re-matched later, so a note added or
    /// renamed in between cannot change what gets deleted.
    var noteIDs: [UUID]
    var noteTitles: [String]
    var isDestructive: Bool = true
}

/// Transient, app-wide messaging: one-line notices ("I cleared your search so you could see it")
/// and the Undo affordance after any change to the notes.
struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var actionLabel: String? = nil
    /// When set, the action button opens this note rather than just dismissing the notice.
    var noteID: UUID? = nil
    /// "Undo" is a different action from opening a note, so the banner says what it will do.
    var undoes = false
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .notes

    /// Navigation stacks live here so opening a note from Ask, Date or the assistant ends up in the
    /// same place the user would have gone by hand - and so leaving a tab cannot strand a screen.
    @Published var notesPath: [NoteRoute] = []
    @Published var datePath: [NoteRoute] = []

    @Published var searchText: String = ""
    @Published var categoryFilter: String? = nil
    @Published var dateFilter: DateFilterMode = .mostUrgent

    /// Notes touched by the assistant, flashed briefly in the list so "done" is visible even if the
    /// user was looking at another tab when it happened.
    @Published private(set) var recentlyChanged: [UUID] = []
    @Published var pendingConfirmation: PendingConfirmation? = nil
    @Published var notice: AppNotice? = nil
    /// Set when Settings should be presented; the Notes tab owns the sheet, and every other route
    /// to Settings (including the assistant) just flips this.
    @Published var showingSettings = false
    /// Set by `reveal` so the list can scroll the note into view, not just open it. Without this,
    /// "show me what you changed" landed on a screen where the note was further down and unseen.
    @Published var scrollRequest: UUID? = nil
    /// Set when somewhere else wants the user in the Ask tab with a question already typed -
    /// "Ask the AI to remind you about this" used to be a sentence with no button behind it, and the
    /// app could not switch tabs at all.
    @Published var askDraft: String? = nil

    private var flashTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    /// Opens a note where it belongs: in the Notes tab, with the filters that would hide it cleared
    /// out of the way, and a short highlight on the row it came from.
    ///
    /// - Returns: false if the note no longer exists, so callers can say so instead of pushing a
    ///   screen that reads "Note Not Found".
    @discardableResult
    func reveal(noteID: UUID,
                in store: NotesStore,
                highlight: String? = nil,
                highlightLine: String? = nil,
                theme: AppTheme? = nil,
                startEditing: Bool = false,
                flash: Bool = false) -> Bool {
        guard store.notes.contains(where: { $0.id == noteID }) else { return false }

        // A search or category filter that hides this note is the difference between "I did it" and
        // "I see nothing". Clear it and say so, rather than leaving the user to guess.
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let note = store.notes.first(where: { $0.id == noteID })
        var cleared: [String] = []
        if let categoryFilter, let note, note.categoryEnglish != categoryFilter {
            self.categoryFilter = nil
            cleared.append("the \"\(categoryFilter)\" filter")
        }
        if !query.isEmpty, let note,
           !note.title.lowercased().contains(query), !note.body.lowercased().contains(query) {
            searchText = ""
            cleared.append("your search")
        }
        if !cleared.isEmpty {
            say("Cleared \(cleared.joined(and: " and ")) so you could see it.")
        }

        selectedTab = .notes
        notesPath = [NoteRoute(noteID: noteID,
                               highlight: highlight,
                               highlightLine: highlightLine,
                               theme: theme,
                               startEditing: startEditing)]
        scrollRequest = noteID
        if flash { markChanged([noteID]) }
        return true
    }

    /// Pushes a note onto the tab the user is already on - used when the answer belongs to the Ask
    /// conversation itself, where losing the chat behind a full-screen note is the wrong trade.
    @discardableResult
    func push(in tab: AppTab, _ route: NoteRoute, on store: NotesStore) -> Bool {
        guard store.notes.contains(where: { $0.id == route.noteID }) else { return false }
        switch tab {
        case .notes: notesPath.append(route)
        case .date: datePath.append(route)
        case .ask: selectedTab = .ask
        }
        return true
    }

    func popCurrentTab() {
        switch selectedTab {
        case .notes: notesPath = []
        case .date: datePath = []
        case .ask: break
        }
    }

    func setFilter(category: String?, search: String? = nil) {
        categoryFilter = category
        if let search { searchText = search }
        selectedTab = .notes
    }

    func clearFilters() {
        let hadFilters = searchText.isEmpty == false || categoryFilter != nil
        searchText = ""
        categoryFilter = nil
        if hadFilters { say("Cleared the filters.") }
    }

    func markChanged(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        recentlyChanged = ids
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.recentlyChanged = [] }
        }
    }

    func say(_ text: String, actionLabel: String? = nil, noteID: UUID? = nil, undoes: Bool = false) {
        notice = AppNotice(text: text, actionLabel: actionLabel, noteID: noteID, undoes: undoes)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.notice = nil }
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    // MARK: - Confirmations

    func request(_ confirmation: PendingConfirmation) {
        pendingConfirmation = confirmation
        say("\(confirmation.question) Confirm in the Ask tab.", actionLabel: "Review")
    }

    /// A user typing "yes"/"do it"/"confirm" is an acceptable answer to a pending change; making
    /// them hunt for a button inside an old chat bubble was a real source of "it never did it".
    static func isAffirmative(_ text: String) -> Bool {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 4 else { return false }
        let yes: Set<String> = ["yes", "yeah", "yep", "sure", "ok", "okay", "do", "it", "confirm",
                                "delete", "remove", "go", "ahead", "please", "yesdo", "y"]
        return !Set(words).isDisjoint(with: yes) && words.allSatisfy { yes.contains($0) }
    }

    static func isNegative(_ text: String) -> Bool {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 4 else { return false }
        let no: Set<String> = ["no", "dont", "do", "not", "keep", "it", "cancel", "nevermind",
                               "nope", "stop", "n"]
        return words.contains("no") || words.contains("nope") || words.contains("cancel")
            || words.contains("keep") || words.contains("n")
    }
}

extension [String] {
    /// "a", "a and b", "a, b and c" - the plain-English join macOS/iOS alerts use.
    func joined(and: String) -> String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        default: return dropLast().joined(separator: ", ") + " \(and) " + self[count - 1]
        }
    }
}
