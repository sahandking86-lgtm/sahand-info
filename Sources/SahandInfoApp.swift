import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Design System

private enum Layout {
    static let cornerRadius: CGFloat = 18
}

extension Color {
    static let brandStart = Color(red: 0.40, green: 0.36, blue: 0.98)
    static let brandEnd = Color(red: 0.72, green: 0.34, blue: 0.86)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [.brandStart, .brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case classic, sunset, forest, ocean, rose, amber, mint, berry, slate, plum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .rose: return "Rose"
        case .amber: return "Amber"
        case .mint: return "Mint"
        case .berry: return "Berry"
        case .slate: return "Slate"
        case .plum: return "Plum"
        }
    }

    var startColor: Color {
        switch self {
        case .classic: return Color(red: 0.40, green: 0.36, blue: 0.98)
        case .sunset: return Color(red: 0.98, green: 0.42, blue: 0.32)
        case .forest: return Color(red: 0.13, green: 0.50, blue: 0.36)
        case .ocean: return Color(red: 0.10, green: 0.50, blue: 0.78)
        case .rose: return Color(red: 0.90, green: 0.36, blue: 0.56)
        case .amber: return Color(red: 0.95, green: 0.65, blue: 0.10)
        case .mint: return Color(red: 0.10, green: 0.70, blue: 0.55)
        case .berry: return Color(red: 0.55, green: 0.10, blue: 0.35)
        case .slate: return Color(red: 0.30, green: 0.36, blue: 0.44)
        case .plum: return Color(red: 0.45, green: 0.20, blue: 0.55)
        }
    }

    var endColor: Color {
        switch self {
        case .classic: return Color(red: 0.72, green: 0.34, blue: 0.86)
        case .sunset: return Color(red: 0.98, green: 0.72, blue: 0.24)
        case .forest: return Color(red: 0.42, green: 0.78, blue: 0.44)
        case .ocean: return Color(red: 0.40, green: 0.80, blue: 0.86)
        case .rose: return Color(red: 0.98, green: 0.62, blue: 0.70)
        case .amber: return Color(red: 0.99, green: 0.84, blue: 0.35)
        case .mint: return Color(red: 0.55, green: 0.92, blue: 0.78)
        case .berry: return Color(red: 0.85, green: 0.30, blue: 0.55)
        case .slate: return Color(red: 0.58, green: 0.66, blue: 0.74)
        case .plum: return Color(red: 0.72, green: 0.48, blue: 0.82)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [startColor, endColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Layout.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = Layout.cornerRadius) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

private let absoluteDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

// MARK: - Model

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
}

extension Note {
    var previewText: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No additional text" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Notes persistence

final class NotesStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { save() }
    }

    private let storageKey = "sahand_info_notes_v1"

    init() {
        load()
        if notes.isEmpty {
            notes = [
                Note(
                    title: "Welcome",
                    body: "This is your first note. Tap the pencil icon to edit it, or tap + on the Notes tab to add a new one.\n\nTry writing something like:\n10/10/2025 Abc Restaurant entry = 20$\n\nThen go to the Ask tab and type: how much does abc restaurant entry cost?"
                )
            ]
        }
    }

    func add(_ note: Note) {
        notes.append(note)
    }

    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
    }

    func delete(ids: [UUID]) {
        notes.removeAll { ids.contains($0.id) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }
}

// MARK: - Settings

enum AnswerMode: String, Codable, CaseIterable, Identifiable {
    case aiAnswer
    case jumpAndHighlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiAnswer: return "AI Answer"
        case .jumpAndHighlight: return "Jump & Highlight"
        }
    }

    var explanation: String {
        switch self {
        case .aiAnswer:
            return "Shows a short written answer plus a tappable note card."
        case .jumpAndHighlight:
            return "Jumps straight into the matching note and highlights the answer."
        }
    }
}

final class SettingsStore: ObservableObject {
    @Published var answerMode: AnswerMode {
        didSet {
            UserDefaults.standard.set(answerMode.rawValue, forKey: storageKey)
        }
    }

    @Published var useOnlineAI: Bool {
        didSet {
            UserDefaults.standard.set(useOnlineAI, forKey: onlineStorageKey)
        }
    }

    @Published var deepSeekAPIKey: String {
        didSet {
            UserDefaults.standard.set(deepSeekAPIKey, forKey: apiKeyStorageKey)
        }
    }

    @Published var notePattern: String {
        didSet {
            UserDefaults.standard.set(notePattern, forKey: notePatternStorageKey)
        }
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: themeStorageKey)
        }
    }

    private let storageKey = "sahand_info_answer_mode_v1"
    private let onlineStorageKey = "sahand_info_use_online_ai_v1"
    private let apiKeyStorageKey = "sahand_info_deepseek_api_key_v1"
    private let notePatternStorageKey = "sahand_info_note_pattern_v1"
    private let themeStorageKey = "sahand_info_theme_v1"

    init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let mode = AnswerMode(rawValue: raw) {
            answerMode = mode
        } else {
            answerMode = .aiAnswer
        }
        useOnlineAI = UserDefaults.standard.bool(forKey: onlineStorageKey)
        deepSeekAPIKey = UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
        notePattern = UserDefaults.standard.string(forKey: notePatternStorageKey) ?? ""
        if let rawTheme = UserDefaults.standard.string(forKey: themeStorageKey),
           let savedTheme = AppTheme(rawValue: rawTheme) {
            theme = savedTheme
        } else {
            theme = .classic
        }
    }
}

// MARK: - Question answering engine

struct AnswerResult: Equatable {
    let matchedNote: Note
    let matchedLine: String
    let extractedAnswer: String
    let sentence: String
}

enum QuestionAnswerer {

    static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "do", "does", "did",
        "how", "what", "when", "where", "who", "why", "which", "much", "many",
        "of", "for", "in", "on", "at", "to", "and", "or", "i", "you", "it",
        "this", "that", "my", "your", "me", "will", "can", "could", "would",
        "should", "about", "tell"
    ]

    static let synonyms: [String: Set<String>] = [
        "cost": ["cost", "costs", "price", "prices", "fee", "fees", "charge", "charges", "entry", "amount", "paid", "pay", "expensive"],
        "price": ["price", "cost", "costs", "fee", "charge", "amount"],
        "when": ["when", "date", "day", "time", "last"],
        "date": ["date", "day", "when", "time"],
        "phone": ["phone", "number", "call", "contact"],
        "where": ["where", "location", "address", "place"],
        "who": ["who", "name", "person"]
    ]

    static let moneyHints: Set<String> = ["cost", "costs", "price", "prices", "fee", "fees", "charge", "charges", "dollar", "dollars", "usd", "pay", "paid", "expensive", "amount"]
    static let dateHints: Set<String> = ["when", "date", "day", "time", "last"]
    static let phoneHints: Set<String> = ["phone", "call", "contact"]
    static let percentHints: Set<String> = ["percent", "percentage", "rate"]

    // Hoisted so extraction and line-scoring share the same pattern set.
    static let moneyPatterns = [
        #"\$\s?\d+(?:[.,]\d+)?"#,
        #"\d+(?:[.,]\d+)?\s?(?:\$|dollars|usd)"#
    ]
    static let percentPatterns = [#"\d+(?:\.\d+)?\s?%"#]
    static let datePatterns = [#"\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}"#]
    static let phonePatterns = [#"\d{3}[-.\s]?\d{3}[-.\s]?\d{4}"#]
    static let numberPatterns = [#"\d+(?:\.\d+)?"#]

    /// What kind of value the question is actually asking for. Knowing this lets
    /// extraction go straight for the right pattern in the line — a date, a price, a
    /// phone number — instead of guessing from position (e.g. "whatever's after the
    /// '=' sign"), which breaks the moment a line has more than one kind of value on it.
    enum ValueCategory {
        case date, phone, percent, money, generic
    }

    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var cleaned = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                cleaned.unicodeScalars.append(scalar)
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    static func expand(_ tokens: [String]) -> Set<String> {
        var expanded = Set(tokens)
        for token in tokens {
            if let related = synonyms[token] {
                expanded.formUnion(related)
            }
        }
        return expanded
    }

    /// Date is checked first: "when", "last [time]" etc. are unambiguous asks for a
    /// date, and should win even when the matched line also happens to contain a price.
    static func expectedCategory(for hints: Set<String>) -> ValueCategory {
        if !hints.isDisjoint(with: dateHints) { return .date }
        if !hints.isDisjoint(with: phoneHints) { return .phone }
        if !hints.isDisjoint(with: percentHints) { return .percent }
        if !hints.isDisjoint(with: moneyHints) { return .money }
        return .generic
    }

    static func regexPatterns(for category: ValueCategory) -> [String] {
        switch category {
        case .date: return datePatterns
        case .phone: return phonePatterns
        case .percent: return percentPatterns
        case .money: return moneyPatterns
        case .generic: return []
        }
    }

    static func firstMatch(of patterns: [String], in line: String) -> String? {
        for pattern in patterns {
            if let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(line[range])
            }
        }
        return nil
    }

    static func topMatchingNotes(for question: String, in notes: [Note], limit: Int = 3) -> [Note] {
        let rawTokens = tokenize(question)
        let questionTokens = rawTokens.filter { !stopWords.contains($0) }
        guard !questionTokens.isEmpty else { return [] }
        let expandedQuestionTokens = expand(questionTokens)

        let scored: [(Note, Double)] = notes.compactMap { note in
            let noteTokens = tokenize(note.title + " " + note.body)
            guard !noteTokens.isEmpty else { return nil }
            let overlap = expandedQuestionTokens.intersection(Set(noteTokens)).count
            guard overlap > 0 else { return nil }
            return (note, Double(overlap) / Double(noteTokens.count).squareRoot())
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// Finds which existing note an AI command like "update the X note" or "delete X" is referring to.
    static func bestMatchingNote(for target: String, in notes: [Note]) -> Note? {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedTarget.isEmpty else { return nil }

        if let exact = notes.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedTarget }) {
            return exact
        }
        if let contains = notes.first(where: {
            !$0.title.isEmpty && ($0.title.lowercased().contains(trimmedTarget) || trimmedTarget.contains($0.title.lowercased()))
        }) {
            return contains
        }
        return topMatchingNotes(for: target, in: notes, limit: 1).first
    }

    static func answer(for question: String, in notes: [Note]) -> AnswerResult? {
        let rawTokens = tokenize(question)
        let questionTokens = rawTokens.filter { !stopWords.contains($0) }
        guard !questionTokens.isEmpty else { return nil }
        let expandedQuestionTokens = expand(questionTokens)
        let category = expectedCategory(for: expandedQuestionTokens)

        // Pick the best matching note, normalized by note length so a short, focused
        // note isn't drowned out by a long note that merely shares a few words.
        var bestNote: Note? = nil
        var bestNoteScore = 0.0

        for note in notes {
            let noteTokens = tokenize(note.title + " " + note.body)
            guard !noteTokens.isEmpty else { continue }
            let noteTokenSet = Set(noteTokens)
            let overlap = expandedQuestionTokens.intersection(noteTokenSet).count
            guard overlap > 0 else { continue }
            let normalized = Double(overlap) / Double(noteTokens.count).squareRoot()
            if normalized > bestNoteScore {
                bestNoteScore = normalized
                bestNote = note
            }
        }

        guard let matchedNote = bestNote else { return nil }

        let lines = matchedNote.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let candidateLines = lines.isEmpty ? [matchedNote.body] : lines

        // Score each line by keyword overlap, with a strong boost for a line that
        // actually contains the kind of value being asked about — so "when did I go"
        // picks the line with a date on it even if a different line mentions the
        // restaurant more times, and even if that same line also has a price on it.
        var bestLine = candidateLines[0]
        var bestLineScore = -1.0
        for line in candidateLines {
            let lineTokens = Set(tokenize(line))
            var score = Double(expandedQuestionTokens.intersection(lineTokens).count)
            if category != .generic, firstMatch(of: regexPatterns(for: category), in: line) != nil {
                score += 1.0
            }
            if score > bestLineScore {
                bestLineScore = score
                bestLine = line
            }
        }

        let extracted = extractAnswerValue(from: bestLine, category: category, hints: expandedQuestionTokens)

        let title = matchedNote.title.isEmpty ? "Untitled" : matchedNote.title
        let sentence = "From the \"\(title)\" note: \(extracted)"

        return AnswerResult(
            matchedNote: matchedNote,
            matchedLine: bestLine,
            extractedAnswer: extracted,
            sentence: sentence
        )
    }

    /// Picks the value out of the matched line. If the question clearly signals a
    /// specific kind of value (a date, a phone number, a price, a percentage), that
    /// exact pattern is searched for directly, wherever it sits in the line — this is
    /// what makes "when did I go" return the date even when a price sits right next to
    /// it. Only when the question doesn't signal a specific type do we fall back to
    /// reading whatever follows a "label = value" style delimiter, and finally to any
    /// number-shaped token in the line as a last resort.
    static func extractAnswerValue(from line: String, category: ValueCategory, hints: Set<String>) -> String {
        if category != .generic, let typed = firstMatch(of: regexPatterns(for: category), in: line) {
            return typed
        }
        if let structured = extractStructuredValue(from: line, hints: hints) {
            return structured
        }
        let fallbackPatterns = datePatterns + moneyPatterns + percentPatterns + phonePatterns + numberPatterns
        if let anyValue = firstMatch(of: fallbackPatterns, in: line) {
            return anyValue
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// Parses simple "Label = Value" / "Label: Value" / "Label - Value" notes and
    /// returns the value directly when the label matches what's being asked about.
    /// Used only once a specific value type has already been ruled out, since a plain
    /// label/value split can't tell a date sitting in the label from a price in the
    /// value — that distinction is what regexPatterns(for:) above is for.
    static func extractStructuredValue(from line: String, hints: Set<String>) -> String? {
        let delimiters = ["=", ":", " - ", " – "]
        for delimiter in delimiters {
            guard let range = line.range(of: delimiter) else { continue }
            let label = String(line[line.startIndex..<range.lowerBound])
            let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            let labelTokens = Set(tokenize(label))
            guard !labelTokens.isEmpty, !labelTokens.isDisjoint(with: hints) else { continue }
            return value
        }
        return nil
    }
}

// MARK: - Notes list

struct NotesListView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    @State private var path: [NoteDestination] = []
    @State private var searchText = ""
    @State private var didTapAdd = false

    struct NoteDestination: Hashable {
        let id: UUID
        var startEditing: Bool = false
    }

    private var sortedNotes: [Note] {
        notesStore.notes.sorted { $0.dateModified > $1.dateModified }
    }

    private var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedNotes }
        return sortedNotes.filter {
            $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if sortedNotes.isEmpty {
                        ContentUnavailableView {
                            Label("No Notes Yet", systemImage: "note.text")
                        } description: {
                            Text("Tap the button below to create your first note.")
                        }
                    } else if filteredNotes.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            ForEach(filteredNotes) { note in
                                NavigationLink(value: NoteDestination(id: note.id)) {
                                    NoteRowView(note: note)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .animation(.snappy, value: filteredNotes)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

                // Always visible now — previously this hid whenever the notes list
                // was empty, even though the empty-state message told people to
                // "tap the button below" to create their first note.
                Button(action: addNewNote) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(settings.theme.gradient, in: Circle())
                        .shadow(color: settings.theme.endColor.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .sensoryFeedback(.impact(weight: .medium), trigger: didTapAdd)
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
            .navigationDestination(for: NoteDestination.self) { dest in
                NoteDetailView(noteID: dest.id, startInEditMode: dest.startEditing)
            }
        }
    }

    private func addNewNote() {
        didTapAdd.toggle()
        let newNote = Note(title: "", body: "")
        notesStore.add(newNote)
        path.append(NoteDestination(id: newNote.id, startEditing: true))
    }

    private func delete(_ note: Note) {
        withAnimation(.snappy) {
            notesStore.delete(ids: [note.id])
        }
    }
}

struct NoteRowView: View {
    @EnvironmentObject var settings: SettingsStore
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(settings.theme.gradient)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(relativeDateFormatter.localizedString(for: note.dateModified, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .cardBackground()
    }
}

// MARK: - Note detail / editor

struct NoteDetailView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    let noteID: UUID
    var highlightText: String? = nil
    var highlightColor: Color = .purple
    var startInEditMode: Bool = false

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var didSave = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, body
    }

    private var note: Note? {
        notesStore.notes.first(where: { $0.id == noteID })
    }

    var body: some View {
        Group {
            if let note {
                Group {
                    if isEditing {
                        editingView
                    } else {
                        readingView(note: note)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(isEditing ? "Edit Note" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            handleToolbarTap(note: note)
                        } label: {
                            Text(isEditing ? "Save" : "Edit")
                                .fontWeight(.semibold)
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .fontWeight(.semibold)
                    }
                }
                .sensoryFeedback(.success, trigger: didSave)
                .onAppear {
                    guard startInEditMode, !isEditing else { return }
                    draftTitle = note.title
                    draftBody = note.body
                    isEditing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        focusedField = .title
                    }
                }
                .onDisappear {
                    // Bug fix: tapping "+" creates a real, empty note right away so it
                    // can be navigated to in edit mode. Previously, backing out of that
                    // screen without tapping "Save" left a permanent blank "Untitled"
                    // note behind. Now an abandoned brand-new note is discarded instead.
                    guard startInEditMode, isEditing else { return }
                    let emptyTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let emptyBody = draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if emptyTitle && emptyBody {
                        notesStore.delete(ids: [noteID])
                    }
                }
            } else {
                ContentUnavailableView("Note Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draftTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .body }
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // A soft fading gradient instead of a hard system Divider — feels less
            // like a form field and more like part of the note.
            LinearGradient(
                colors: [settings.theme.endColor.opacity(0.4), settings.theme.startColor.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
            .clipShape(Capsule())
            .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                if draftBody.isEmpty {
                    Text("Start writing…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftBody)
                    .focused($focusedField, equals: .body)
                    .scrollContentBackground(.hidden)
            }
            .font(.body)
            .padding(.horizontal, 15)
            .frame(maxHeight: .infinity)
        }
    }

    private func readingView(note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(highlightedAttributedString(body: note.body, highlight: highlightText, color: highlightColor))
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LinearGradient(
                    colors: [settings.theme.endColor.opacity(0.3), settings.theme.startColor.opacity(0.03)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1.5)
                .clipShape(Capsule())
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Created \(absoluteDateFormatter.string(from: note.dateCreated))", systemImage: "calendar")
                    Label("Edited \(relativeDateFormatter.localizedString(for: note.dateModified, relativeTo: Date()))", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func handleToolbarTap(note: Note) {
        if isEditing {
            saveDraft(originalNote: note)
            focusedField = nil
            didSave.toggle()
        } else {
            draftTitle = note.title
            draftBody = note.body
            focusedField = .title
        }
        withAnimation(.snappy) { isEditing.toggle() }
    }

    private func saveDraft(originalNote: Note) {
        var updated = originalNote
        updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : draftTitle
        updated.body = draftBody
        updated.dateModified = Date()
        notesStore.update(updated)
    }

    private func highlightedAttributedString(body: String, highlight: String?, color: Color) -> AttributedString {
        guard let highlight, !highlight.isEmpty,
              let stringRange = body.range(of: highlight, options: [.caseInsensitive]) else {
            return AttributedString(body)
        }

        let prefix = String(body[body.startIndex..<stringRange.lowerBound])
        let match = String(body[stringRange])
        let suffix = String(body[stringRange.upperBound...])

        var matchAttr = AttributedString(match)
        matchAttr.backgroundColor = color.opacity(0.45)
        matchAttr.foregroundColor = Color.primary

        return AttributedString(prefix) + matchAttr + AttributedString(suffix)
    }
}

// MARK: - Ask tab (chat-style)

enum PendingUndoAction: Equatable {
    case restoreNote(Note)
    case removeNote(UUID)
}

/// A tappable chip for a note the AI drew its answer from, colored with a randomly assigned theme.
struct SourceNoteChip: Identifiable, Equatable {
    let id: UUID // the note's own id
    let title: String
    let theme: AppTheme
}

/// One piece of an AI answer, optionally tied to a source note (and colored to match its chip).
struct ResolvedAnswerSegment: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var noteID: UUID?
    var excerpt: String?
    var theme: AppTheme?
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case userQuestion(String)
        case answerCard(AnswerResult)
        case plainText(String)
        case actionResult(text: String, undo: PendingUndoAction?)
        case confirmDelete(note: Note)
        case sourcedAnswer(chips: [SourceNoteChip], segments: [ResolvedAnswerSegment])
    }

    var id: UUID = UUID()
    let kind: Kind
}

private struct ChatBubbleUser: View {
    @EnvironmentObject var settings: SettingsStore
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(settings.theme.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .textSelection(.enabled)
        }
    }
}

private struct ChatBubbleAssistantPlain: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 40)
        }
    }
}

struct AskView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore

    @State private var questionText = ""
    @State private var messages: [ChatMessage] = []
    @State private var path: [AskDestination] = []
    @State private var didAsk = false
    @State private var conversationHistory: [ConversationTurn] = []
    @FocusState private var isInputFocused: Bool

    struct AskDestination: Hashable {
        let noteID: UUID
        let highlight: String?
        var highlightColor: Color? = nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Group {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        chatScrollView
                    }
                }
                // Tapping any empty space above the input bar dismisses the keyboard.
                // simultaneousGesture (rather than onTapGesture) so buttons inside —
                // the note chip, the trash icon — still register their own taps too.
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })

                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AskDestination.self) { dest in
                NoteDetailView(noteID: dest.noteID, highlightText: dest.highlight, highlightColor: dest.highlightColor ?? .purple)
            }
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            withAnimation(.snappy) { messages.removeAll() }
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: didAsk)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(settings.theme.gradient)
            Text("Ask your notes")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Get quick answers pulled straight from what you've written.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        messageView(for: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func messageView(for message: ChatMessage) -> some View {
        switch message.kind {
        case .userQuestion(let text):
            ChatBubbleUser(text: text)
        case .answerCard(let result):
            HStack(alignment: .top, spacing: 0) {
                AnswerCardView(result: result) {
                    path.append(AskDestination(noteID: result.matchedNote.id, highlight: result.extractedAnswer))
                }
                .frame(maxWidth: 320, alignment: .leading)
                Spacer(minLength: 24)
            }
        case .plainText(let text):
            ChatBubbleAssistantPlain(text: text)
        case .actionResult(let text, let undo):
            VStack(alignment: .leading, spacing: 6) {
                ChatBubbleAssistantPlain(text: text)
                if let undo {
                    HStack {
                        Button {
                            performUndo(undo)
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer(minLength: 40)
                    }
                }
            }
        case .confirmDelete(let note):
            VStack(alignment: .leading, spacing: 8) {
                ChatBubbleAssistantPlain(text: "Delete \"\(note.title.isEmpty ? "Untitled" : note.title)\"? This can't be undone.")
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        confirmPendingDelete(note: note, messageID: message.id)
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)

                    Button {
                        cancelPendingDelete(messageID: message.id)
                    } label: {
                        Text("Keep it")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 24)
                }
            }
        case .sourcedAnswer(let chips, let segments):
            VStack(alignment: .leading, spacing: 10) {
                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips) { chip in
                                Button {
                                    openSourceNote(chip: chip, segments: segments)
                                } label: {
                                    Text(chip.title)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(chip.theme.gradient, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 16)
                    }
                }

                HStack {
                    sourcedAnswerText(segments: segments)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .textSelection(.enabled)
                    Spacer(minLength: 24)
                }
            }
        }
    }

    private func sourcedAnswerText(segments: [ResolvedAnswerSegment]) -> Text {
        var result = AttributedString("")
        for segment in segments {
            var attr = AttributedString(segment.text)
            if let theme = segment.theme {
                attr.backgroundColor = theme.startColor.opacity(0.35)
                attr.foregroundColor = Color.primary
            }
            result += attr
        }
        return Text(result)
    }

    private func openSourceNote(chip: SourceNoteChip, segments: [ResolvedAnswerSegment]) {
        let excerpt = segments.first(where: { $0.noteID == chip.id })?.excerpt
        path.append(AskDestination(noteID: chip.id, highlight: excerpt, highlightColor: chip.theme.startColor))
    }

    private func performUndo(_ undo: PendingUndoAction) {
        switch undo {
        case .restoreNote(let note):
            notesStore.update(note)
        case .removeNote(let id):
            notesStore.delete(ids: [id])
        }
    }

    private func confirmPendingDelete(note: Note, messageID: UUID) {
        notesStore.delete(ids: [note.id])
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            withAnimation(.snappy) {
                messages[index] = ChatMessage(id: messageID, kind: .plainText("Deleted \"\(note.title.isEmpty ? "Untitled" : note.title)\"."))
            }
        }
    }

    private func cancelPendingDelete(messageID: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            withAnimation(.snappy) {
                messages[index] = ChatMessage(id: messageID, kind: .plainText("Okay, kept it."))
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask something…", text: $questionText, axis: .vertical)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(sendQuestion)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())

            Button(action: sendQuestion) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(settings.theme.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Resigns the on-screen keyboard. Clears the FocusState binding and also
    /// forces first-responder resignation as a safety net, since a vertical-axis
    /// TextField can occasionally ignore the FocusState change on its own.
    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func sendQuestion() {
        let trimmed = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismissKeyboard()
        didAsk.toggle()
        questionText = ""

        withAnimation(.snappy) {
            messages.append(ChatMessage(kind: .userQuestion(trimmed)))
        }

        switch settings.answerMode {
        case .jumpAndHighlight:
            if let result = QuestionAnswerer.answer(for: trimmed, in: notesStore.notes) {
                let noteTitle = result.matchedNote.title.isEmpty ? "Untitled" : result.matchedNote.title
                withAnimation(.snappy) {
                    messages.append(ChatMessage(kind: .plainText("Found it in \"\(noteTitle)\" — opening now.")))
                }
                path.append(AskDestination(noteID: result.matchedNote.id, highlight: result.extractedAnswer))
            } else {
                withAnimation(.snappy) {
                    messages.append(ChatMessage(kind: .plainText("I couldn't find an answer to that in your notes. Try different words or add more detail.")))
                }
            }

        case .aiAnswer:
            let thinkingID = UUID()
            withAnimation(.snappy) {
                messages.append(ChatMessage(id: thinkingID, kind: .plainText("Thinking…")))
            }
            let searchSeed = (conversationHistory.suffix(2).map { $0.text } + [trimmed]).joined(separator: " ")
            let relevantNotes = QuestionAnswerer.topMatchingNotes(for: searchSeed, in: notesStore.notes)
            let historySnapshot = conversationHistory
            Task {
                let rawText = settings.useOnlineAI
                    ? await OnlineAI.answer(question: trimmed, relevantNotes: relevantNotes, apiKey: settings.deepSeekAPIKey, history: historySnapshot, notePattern: settings.notePattern)
                    : await LocalAI.shared.answer(question: trimmed, relevantNotes: relevantNotes)

                let parsed = AIProtocol.parse(rawText)
                var replyText = parsed.reply
                var pendingUndo: PendingUndoAction? = nil
                var pendingDelete: Note? = nil
                var sourcedKind: ChatMessage.Kind? = nil

                switch parsed.action {
                case "create_note":
                    let title = (parsed.title?.isEmpty == false) ? parsed.title! : "Untitled"
                    let newNote = Note(title: title, body: parsed.content ?? "")
                    notesStore.add(newNote)
                    pendingUndo = .removeNote(newNote.id)

                case "update_note":
                    if let targetText = parsed.target,
                       let match = QuestionAnswerer.bestMatchingNote(for: targetText, in: notesStore.notes) {
                        let original = match
                        var updated = match
                        updated.body = parsed.content ?? match.body
                        updated.dateModified = Date()
                        notesStore.update(updated)
                        pendingUndo = .restoreNote(original)
                    } else {
                        replyText = "I couldn't figure out which note to update. Try naming it more specifically."
                    }

                case "delete_note":
                    if let targetText = parsed.target,
                       let match = QuestionAnswerer.bestMatchingNote(for: targetText, in: notesStore.notes) {
                        pendingDelete = match
                    } else {
                        replyText = "I couldn't figure out which note to delete. Try naming it more specifically."
                    }

                default:
                    sourcedKind = buildSourcedAnswerKind(parsed: parsed, replyText: replyText)
                }

                conversationHistory.append(ConversationTurn(role: "user", text: trimmed))
                conversationHistory.append(ConversationTurn(role: "model", text: replyText))
                if conversationHistory.count > 20 {
                    conversationHistory = Array(conversationHistory.suffix(20))
                }

                if let index = messages.firstIndex(where: { $0.id == thinkingID }) {
                    withAnimation(.snappy) {
                        if let pendingDelete {
                            messages[index] = ChatMessage(id: thinkingID, kind: .confirmDelete(note: pendingDelete))
                        } else if let sourcedKind {
                            messages[index] = ChatMessage(id: thinkingID, kind: sourcedKind)
                        } else {
                            messages[index] = ChatMessage(id: thinkingID, kind: .actionResult(text: replyText, undo: pendingUndo))
                        }
                    }
                }
            }
        }
    }

    /// Tries to build a colored, source-attributed answer from the AI's segments.
    /// Falls back to nil (plain text) if the segments don't reconstruct the reply exactly,
    /// or don't resolve to any real notes — so a slip-up from the AI never breaks the answer.
    private func buildSourcedAnswerKind(parsed: AIActionResponse, replyText: String) -> ChatMessage.Kind? {
        guard !parsed.segments.isEmpty else { return nil }

        let reconstructed = parsed.segments.map(\.text).joined()
        guard reconstructed.trimmingCharacters(in: .whitespacesAndNewlines) == replyText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        var seenTitles: [String] = []
        for segment in parsed.segments {
            if let title = segment.sourceNote, !title.isEmpty, !seenTitles.contains(title) {
                seenTitles.append(title)
            }
        }
        guard !seenTitles.isEmpty else { return nil }

        var pool = AppTheme.allCases.filter { $0 != settings.theme }.shuffled()
        if pool.isEmpty { pool = AppTheme.allCases.shuffled() }

        var titleToTheme: [String: AppTheme] = [:]
        var titleToNoteID: [String: UUID] = [:]
        var chips: [SourceNoteChip] = []

        for (index, title) in seenTitles.enumerated() {
            guard let note = QuestionAnswerer.bestMatchingNote(for: title, in: notesStore.notes) else { continue }
            let theme = pool[index % pool.count]
            titleToTheme[title] = theme
            titleToNoteID[title] = note.id
            chips.append(SourceNoteChip(id: note.id, title: note.title.isEmpty ? "Untitled" : note.title, theme: theme))
        }
        guard !chips.isEmpty else { return nil }

        let resolvedSegments: [ResolvedAnswerSegment] = parsed.segments.map { segment in
            let noteID = segment.sourceNote.flatMap { titleToNoteID[$0] }
            let theme = segment.sourceNote.flatMap { titleToTheme[$0] }
            return ResolvedAnswerSegment(text: segment.text, noteID: noteID, excerpt: segment.sourceExcerpt, theme: noteID != nil ? theme : nil)
        }

        return .sourcedAnswer(chips: chips, segments: resolvedSegments)
    }
}

struct AnswerCardView: View {
    @EnvironmentObject var settings: SettingsStore
    let result: AnswerResult
    let onTapNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(settings.theme.gradient)
                Text("Answer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(result.sentence)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTapNote) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                    Text(result.matchedNote.title.isEmpty ? "Untitled" : result.matchedNote.title)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardBackground()
    }
}

// MARK: - Settings tab

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var notesStore: NotesStore

    @State private var pendingExportURL: URL?
    @State private var showingImporter = false
    @State private var importStatusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("How should the Ask tab answer you?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(AnswerMode.allCases) { mode in
                        Button {
                            withAnimation(.snappy) { settings.answerMode = mode }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: mode == .aiAnswer ? "sparkles" : "arrow.right.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(settings.theme.endColor)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(mode.explanation)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)

                                if settings.answerMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(settings.theme.endColor)
                                        .font(.title3)
                                }
                            }
                            .padding(16)
                            .cardBackground()
                            .overlay(
                                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                                    .stroke(settings.answerMode == mode ? settings.theme.endColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Text("Online AI (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use online AI instead of on-device", isOn: $settings.useOnlineAI)

                        Text(settings.useOnlineAI ? "Currently using: Online AI (Gemini)" : "Currently using: Offline AI (on-device)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if settings.useOnlineAI {
                            SecureField("Gemini API key", text: $settings.deepSeekAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            Text("Uses your own free Gemini API key over WiFi instead of the bundled offline model. Free tier has rate limits, and Google may use free-tier requests to improve their models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .cardBackground()

                    Divider()
                        .padding(.vertical, 4)

                    Text("Note Writing Pattern (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $settings.notePattern)
                            .frame(minHeight: 90)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Give an example of how you like notes written, e.g. \"10/10/2025 Abc Restaurant entry = 20$\" — new notes the AI creates will follow that style. Currently used by Online AI only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .cardBackground()

                    Divider()
                        .padding(.vertical, 4)

                    Text("Theme")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                withAnimation(.snappy) { settings.theme = theme }
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(theme.gradient)
                                        .frame(height: 44)
                                        .overlay(alignment: .topTrailing) {
                                            if settings.theme == theme {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                            }
                                        }
                                    Text(theme.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                                .padding(12)
                                .cardBackground()
                                .overlay(
                                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                                        .stroke(settings.theme == theme ? theme.endColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Text("Backup")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            prepareExport()
                        } label: {
                            Label("Export All Notes", systemImage: "square.and.arrow.up")
                        }

                        if let pendingExportURL {
                            ShareLink(item: pendingExportURL) {
                                Label("Share Backup File", systemImage: "arrow.up.doc")
                            }
                        }

                        Divider()

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import Notes", systemImage: "square.and.arrow.down")
                        }

                        Text("Export saves all your notes to a file you can AirDrop, email, or save to iCloud Drive — keep it somewhere off the phone. After a reset or reinstall, use Import and pick that file to bring everything back. Importing never deletes existing notes; it only adds new ones and updates any that match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let importStatusMessage {
                            Text(importStatusMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .cardBackground()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
    }

    private func prepareExport() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notesStore.notes) else {
            importStatusMessage = "Couldn't prepare the export file."
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "SahandInfoNotes-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            pendingExportURL = url
            importStatusMessage = nil
        } catch {
            importStatusMessage = "Couldn't prepare the export file."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([Note].self, from: data)
                guard !decoded.isEmpty else {
                    importStatusMessage = "That file didn't contain any notes."
                    return
                }
                var addedCount = 0
                var updatedCount = 0
                for imported in decoded {
                    if notesStore.notes.contains(where: { $0.id == imported.id }) {
                        notesStore.update(imported)
                        updatedCount += 1
                    } else {
                        notesStore.add(imported)
                        addedCount += 1
                    }
                }
                var summary = "Imported \(addedCount) new note\(addedCount == 1 ? "" : "s")."
                if updatedCount > 0 {
                    summary += " Updated \(updatedCount) existing note\(updatedCount == 1 ? "" : "s")."
                }
                importStatusMessage = summary
            } catch {
                importStatusMessage = "That file couldn't be read as a notes backup."
            }
        case .failure:
            importStatusMessage = "Import was cancelled or failed."
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            NotesListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
            AskView()
                .tabItem { Label("Ask", systemImage: "questionmark.bubble") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(settings.theme.endColor)
    }
}

@main
struct SahandInfoApp: App {
    @StateObject private var notesStore = NotesStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesStore)
                .environmentObject(settings)
        }
    }
}
