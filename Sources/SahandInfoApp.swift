import SwiftUI
import UIKit

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

    private let storageKey = "sahand_info_answer_mode_v1"

    init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let mode = AnswerMode(rawValue: raw) {
            answerMode = mode
        } else {
            answerMode = .aiAnswer
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
                        .background(Color.brandGradient, in: Circle())
                        .shadow(color: Color.brandEnd.opacity(0.4), radius: 12, x: 0, y: 6)
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
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.brandGradient)
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
    let noteID: UUID
    var highlightText: String? = nil
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
                colors: [Color.brandEnd.opacity(0.4), Color.brandStart.opacity(0.05)],
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

                Text(highlightedAttributedString(body: note.body, highlight: highlightText))
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LinearGradient(
                    colors: [Color.brandEnd.opacity(0.3), Color.brandStart.opacity(0.03)],
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

    private func highlightedAttributedString(body: String, highlight: String?) -> AttributedString {
        guard let highlight, !highlight.isEmpty,
              let stringRange = body.range(of: highlight, options: [.caseInsensitive]) else {
            return AttributedString(body)
        }

        let prefix = String(body[body.startIndex..<stringRange.lowerBound])
        let match = String(body[stringRange])
        let suffix = String(body[stringRange.upperBound...])

        var matchAttr = AttributedString(match)
        matchAttr.backgroundColor = Color.purple.opacity(0.45)
        matchAttr.foregroundColor = Color.primary

        return AttributedString(prefix) + matchAttr + AttributedString(suffix)
    }
}

// MARK: - Ask tab (chat-style)

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case userQuestion(String)
        case answerCard(AnswerResult)
        case plainText(String)
    }

    let id = UUID()
    let kind: Kind
}

private struct ChatBubbleUser: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brandGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    @FocusState private var isInputFocused: Bool

    struct AskDestination: Hashable {
        let noteID: UUID
        let highlight: String?
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
                NoteDetailView(noteID: dest.noteID, highlightText: dest.highlight)
            }
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            withAnimation(.snappy) { messages.removeAll() }
                        } label: {
                            Image(systemName: "trash")
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
                .foregroundStyle(Color.brandGradient)
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
                    .background(Color.brandGradient, in: Circle())
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

        let answer = QuestionAnswerer.answer(for: trimmed, in: notesStore.notes)

        switch (answer, settings.answerMode) {
        case let (.some(result), .aiAnswer):
            withAnimation(.snappy) {
                messages.append(ChatMessage(kind: .answerCard(result)))
            }
        case let (.some(result), .jumpAndHighlight):
            let noteTitle = result.matchedNote.title.isEmpty ? "Untitled" : result.matchedNote.title
            withAnimation(.snappy) {
                messages.append(ChatMessage(kind: .plainText("Found it in \"\(noteTitle)\" — opening now.")))
            }
            path.append(AskDestination(noteID: result.matchedNote.id, highlight: result.extractedAnswer))
        case (.none, _):
            withAnimation(.snappy) {
                messages.append(ChatMessage(kind: .plainText("I couldn't find an answer to that in your notes. Try different words or add more detail.")))
            }
        }
    }
}

struct AnswerCardView: View {
    let result: AnswerResult
    let onTapNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.brandGradient)
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
                                    .foregroundStyle(Color.brandEnd)
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
                                        .foregroundStyle(Color.brandEnd)
                                        .font(.title3)
                                }
                            }
                            .padding(16)
                            .cardBackground()
                            .overlay(
                                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                                    .stroke(settings.answerMode == mode ? Color.brandEnd : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Root

struct ContentView: View {
    var body: some View {
        TabView {
            NotesListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
            AskView()
                .tabItem { Label("Ask", systemImage: "questionmark.bubble") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Color.brandEnd)
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
