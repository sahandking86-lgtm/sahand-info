import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Design System

private enum Layout {
    static let cornerRadius: CGFloat = 20
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

/// Soft card: gentle fill, wide diffuse shadow, and a hairline border so cards
/// stay visible in dark mode too.
private struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Layout.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = Layout.cornerRadius) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

/// Soft out-of-focus theme-colored glows floating over the system grouped background.
/// Gives every tab a modern, ambient feel that follows the user's chosen theme.
private struct AmbientBackground: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                Circle()
                    .fill(settings.theme.startColor.opacity(0.13))
                    .frame(width: 340, height: 340)
                    .blur(radius: 90)
                    .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.10)
                Circle()
                    .fill(settings.theme.endColor.opacity(0.11))
                    .frame(width: 380, height: 380)
                    .blur(radius: 110)
                    .position(x: proxy.size.width * 0.95, y: proxy.size.height * 0.30)
            }
        }
        .ignoresSafeArea()
    }
}

/// A capsule toggle used for category chips and reminder filters - filled with the theme gradient
/// when selected, quiet card-style when not.
///
/// The fill is one Capsule whose gradient fades in, rather than a swap between two different shape
/// styles. Swapping `AnyShapeStyle` values cannot interpolate, so the previous version popped even
/// though every caller wrapped the change in withAnimation.
private struct SelectablePill: View {
    @EnvironmentObject private var settings: SettingsStore
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .symbolEffect(.bounce, value: isSelected)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                ZStack {
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                    Capsule()
                        .fill(tint.map { LinearGradient(colors: [$0, $0.opacity(0.75)], startPoint: .top, endPoint: .bottom) }
                              ?? settings.theme.gradient)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.07), lineWidth: 1)
            }
            .shadow(color: (tint ?? settings.theme.endColor).opacity(isSelected ? 0.35 : 0), radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.0 : 0.98)
            .animation(.snappy(duration: 0.28), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// Horizontally scrolling "All + each category" chips row shared by the Notes and Date tabs.
///
/// Scrolls to whatever becomes selected: a category the assistant just assigned used to appear at
/// the right-hand end, off screen, with the note list filtered to it - which looked like the note had
/// been hidden rather than tagged.
private struct CategoryChipsRow: View {
    let categories: [String]
    @Binding var selection: String?
    var allLabel: String = "All"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SelectablePill(title: allLabel, isSelected: selection == nil) { selection = nil }
                        .id(Self.allID)
                    ForEach(categories, id: \.self) { category in
                        SelectablePill(title: category, isSelected: selection == category) {
                            selection = category
                        }
                        .id(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else {
                    withAnimation(.snappy) { proxy.scrollTo(Self.allID, anchor: .leading) }
                    return
                }
                withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private static let allID = "__all__"
}

/// Little spring when a button is pressed - used on the FAB and the send button.
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Three bouncing dots while the assistant is working, with a Stop.
///
/// The animation is driven by `isAnimating` and switched off in `onDisappear`: `repeatForever` used
/// to be left running after the answer arrived, so the dots kept moving behind other tabs. The Stop
/// button is the part that was missing entirely - a request that hangs had no way out.
private struct TypingIndicator: View {
    var onStop: (() -> Void)? = nil
    @State private var isAnimating = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(isAnimating ? 1 : 0.55)
                        .opacity(isAnimating ? 1 : 0.35)
                        .animation(
                            isAnimating
                                ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.15)
                                : .easeOut(duration: 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, onStop == nil ? 18 : 10)
            .padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let onStop {
                Button("Stop", action: onStop)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            Spacer(minLength: 48)
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

/// A one-line app-wide notice: what just happened, plus the one follow-up that matters ("Show",
/// "Undo"). Shown on whichever tab the user is looking at, because a change made by the assistant
/// while you were on another tab used to be invisible.
private struct AppNoticeBar: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var notesStore: NotesStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        if let notice = coordinator.notice {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.6)],
                                                             startPoint: .top, endPoint: .bottom)))
                Text(notice.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    // Tapping the words dismisses. This used to be a gesture on the whole bar, which
                    // sat on top of the buttons and could take a tap meant for "Undo".
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.dismissNotice() }
                Spacer(minLength: 8)
                if let label = notice.actionLabel {
                    Button(label) { act(on: notice) }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                Button {
                    coordinator.dismissNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(LinearGradient(colors: [Color.black.opacity(0.72), Color.black.opacity(0.58)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func act(on notice: AppNotice) {
        if notice.undoes {
            if let undone = notesStore.undoLastChange() {
                coordinator.say("Undid: \(undone)")
            }
            return
        }
        if notice.goToAsk {
            coordinator.selectedTab = .ask
            coordinator.dismissNotice()
            return
        }
        if let mode = notice.switchMode {
            settings.answerMode = mode
            coordinator.dismissNotice()
            return
        }
        if notice.opensSettings {
            coordinator.showingSettings = true
            coordinator.dismissNotice()
            return
        }
        if let id = notice.noteID {
            coordinator.reveal(noteID: id, in: notesStore)
        }
        coordinator.dismissNotice()
    }
}

/// The bar that offers to put a change back. Every write to the notes goes through the store's
/// undo stack, so this works for a swipe delete, a bulk delete from the assistant, an import, or
/// clearing everything - the cases where there used to be no way back at all.
private struct UndoBar: View {
    @EnvironmentObject private var notesStore: NotesStore

    var body: some View {
        if let label = notesStore.undoLabel, notesStore.canUndo, notesStore.undoOfferVisible {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    withAnimation(.snappy) { _ = notesStore.undoLastChange() }
                }
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                Button("Later") {
                    // Hides the offer without throwing the undo away: the store still has the
                    // snapshot, so the Ask tab can undo it later.
                    withAnimation(.snappy) { notesStore.hideUndoOffer() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// Marks a note the assistant just changed, so "done" is visible even if you were elsewhere.
private struct ChangedFlash: ViewModifier {
    @EnvironmentObject private var coordinator: AppCoordinator
    let noteID: UUID

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .strokeBorder(Color(red: 0.20, green: 0.78, blue: 0.35),
                                  lineWidth: coordinator.recentlyChanged.contains(noteID) ? 2.5 : 0)
            }
            .animation(.snappy(duration: 0.4), value: coordinator.recentlyChanged)
    }
}

extension View {
    func flashWhenRecentlyChanged(_ noteID: UUID) -> some View {
        modifier(ChangedFlash(noteID: noteID))
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
    var categoryEnglish: String = ""
    var categoryKurdish: String = ""
    var reminderDate: Date? = nil
    var isReminderCompleted: Bool = false
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    // Custom decoding so older exported backups (made before categories/reminders existed)
    // still import cleanly — Swift's auto-synthesized Decodable does NOT fall back to a
    // property's default value when a key is simply missing from the JSON; it would throw
    // instead. Every field added after the original title/body/dateCreated/dateModified is
    // decoded as optional here, defaulting exactly like a freshly created Note would.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        categoryEnglish = try container.decodeIfPresent(String.self, forKey: .categoryEnglish) ?? ""
        categoryKurdish = try container.decodeIfPresent(String.self, forKey: .categoryKurdish) ?? ""
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        isReminderCompleted = try container.decodeIfPresent(Bool.self, forKey: .isReminderCompleted) ?? false
        dateCreated = try container.decodeIfPresent(Date.self, forKey: .dateCreated) ?? Date()
        dateModified = try container.decodeIfPresent(Date.self, forKey: .dateModified) ?? Date()
    }
}

extension Note {
    var previewText: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No additional text" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

/// How pressing a reminder is *compared with the others you are waiting on*. This is the meaning of
/// the colours, in both the Notes list and the Date tab: the nearest few red, the next few amber, the
/// rest green. Counting days instead would make one lonely reminder look calm - or frantic -
/// regardless of what it is the only one of, and the colour would change when a filter was switched,
/// which is why the tier is derived from the whole set once and shared.
enum ReminderTier: Int, Hashable {
    case overdue, urgent, comingUp, later, done

    var color: Color {
        switch self {
        case .overdue: return Color(red: 1.00, green: 0.15, blue: 0.12)
        case .urgent: return Color(red: 1.00, green: 0.30, blue: 0.24)
        case .comingUp: return Color(red: 1.00, green: 0.72, blue: 0.05)
        case .later: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .done: return Color.secondary
        }
    }

    var label: String {
        switch self {
        case .overdue: return "overdue"
        case .urgent: return "urgent"
        case .comingUp: return "coming up"
        case .later: return "later"
        case .done: return "done"
        }
    }

    /// Thirds, nothing more clever than that: the nearest third red, the next third amber, the rest
    /// green. Nine is 3 / 3 / 3, eight is 3 / 3 / 2, seven is 3 / 2 / 2, four is 2 / 1 / 1, and with
    /// one or two reminders waiting the nearest simply is the urgent one.
    static func tiers(of notes: [Note], now: Date = Date()) -> [UUID: ReminderTier] {
        var result: [UUID: ReminderTier] = [:]
        var waiting: [Note] = []
        for note in notes {
            guard let date = note.reminderDate else { continue }
            if note.isReminderCompleted { result[note.id] = .done }
            else if date < now { result[note.id] = .overdue }
            else { waiting.append(note) }
        }
        waiting.sort { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        let count = waiting.count
        // Integer thirds with the remainder pushed to the earlier band, so a short list still has a
        // red row rather than starting at amber.
        let redEnd = (count + 2) / 3
        let amberEnd = (count * 2 + 2) / 3
        for (index, note) in waiting.enumerated() {
            if index < redEnd { result[note.id] = .urgent }
            else if index < amberEnd { result[note.id] = .comingUp }
            else { result[note.id] = .later }
        }
        return result
    }
}

// MARK: - Notes persistence

/// Everything the app knows about your notes, and the only place they are written.
///
/// Every mutation goes through `mutate`, which first pushes a labelled snapshot - so anything can be
/// rolled back, including a delete, which used to try to update a note that no longer existed and so
/// restored nothing. What differs is the announcement: `mutate` raises the Undo banner only when
/// notes actually went away, and stays quiet otherwise. See `offersUndo`.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = [] {
        didSet {
            save()
            // Bumped only when the list actually changed, so views can animate one change rather
            // than re-fading the whole list every time any field of any note differs.
            revision += 1
            ReminderScheduler.shared.sync(with: notes)
        }
    }

    @Published private(set) var revision: Int = 0
    /// What the most recent change was called. The chat's own Undo chip compares against this, so it
    /// can tell "undo the thing this bubble did" from "undo whatever happened last".
    @Published private(set) var undoLabel: String? = nil
    /// Whether the banner is showing. Pressing "Later" hides the banner; it does not make the change
    /// un-undoable, and the assistant can still roll it back from the chat.
    @Published private(set) var undoOfferVisible = false
    /// Bumped by every recorded change. A chat bubble remembers the number it was created with and
    /// only offers Undo while that is still the newest, which is exact - two identical labels ("Marked
    /// a reminder done" twice) would otherwise let an old bubble undo the wrong thing.
    @Published private(set) var undoGeneration = 0

    private var undoStack: [(label: String, notes: [Note])] = []
    private let undoDepth = 15
    private let storageKey = "sahand_info_notes_v1"
    private let seededKey = "sahand_info_seeded_v1"

    init() {
        load()
        // Only ever on the very first launch. Seeding whenever the list happened to be empty meant
        // that clearing everything to start over brought "Welcome" back on the next open.
        if !UserDefaults.standard.bool(forKey: seededKey) {
            UserDefaults.standard.set(true, forKey: seededKey)
            if notes.isEmpty {
                // didSet does not run during init, so without this the Welcome note lived only in
                // memory: relaunch before your first edit and it was gone.
                notes = [
                    Note(
                        title: "Welcome",
                        body: "This is your first note. Tap the pencil icon to edit it, or tap + on the Notes tab to add a new one.\n\nTry writing something like:\n10/10/2025 Abc Restaurant entry = 20$\n\nThen go to the Ask tab and type: how much does abc restaurant entry cost?"
                    )
                ]
                save()
            }
        }
    }

    // MARK: - Reads

    func note(id: UUID) -> Note? { notes.first(where: { $0.id == id }) }

    /// The urgency colour every row should use, computed from all notes so the Notes tab and the Date
    /// tab agree, and so switching a Date filter cannot repaint anything.
    ///
    /// Row views ask for this once per row, so it is cached: ranking is a sort over every note, and
    /// recomputing it for all 500 rows of a long list on every scroll frame is the kind of work that
    /// turns a flash animation into a stutter. The cache is keyed on the data revision and on the
    /// minute, because a reminder turning overdue is the one thing that changes without the data doing
    /// so - a minute of lag on that matches what the rows already display.
    private var tiersCache: (revision: Int, minute: Int, tiers: [UUID: ReminderTier])?
    func reminderTiers() -> [UUID: ReminderTier] {
        let minute = Int(Date().timeIntervalSince1970 / 60)
        if let cache = tiersCache, cache.revision == revision, cache.minute == minute { return cache.tiers }
        let fresh = ReminderTier.tiers(of: notes)
        tiersCache = (revision, minute, fresh)
        return fresh
    }
    var canUndo: Bool { !undoStack.isEmpty }

    /// The Undo bar is an offer, not a hostage: putting it away must not destroy the snapshot.
    func hideUndoOffer() { undoOfferVisible = false }

    /// Notes the Notes tab would actually show for the current search and category chip. The
    /// assistant needs this to say "3 notes match" truthfully instead of counting everything.
    func visibleNotes(search: String, category: String?) -> [Note] {
        var base = notes.sorted { $0.dateModified > $1.dateModified }
        if let category { base = base.filter { $0.categoryEnglish == category } }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
        }
    }

    var allCategories: [String] {
        Array(Set(notes.map { $0.categoryEnglish }.filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Writes

    func add(_ note: Note, label: String? = nil) {
        mutate(label ?? "Added \u{201c}\(displayName(of: note))\u{201d}") { $0 + [note] }
    }

    /// Replaces a note by id, or appends it if the id is gone. That fallback matters: silently
    /// doing nothing on a missing id is how "Undo" after a delete looked like it worked.
    func update(_ note: Note, label: String? = nil) {
        mutate(label ?? "Updated \u{201c}\(displayName(of: note))\u{201d}") { list in
            guard let index = list.firstIndex(where: { $0.id == note.id }) else { return list + [note] }
            var next = list
            next[index] = note
            return next
        }
    }

    func restore(_ note: Note, at index: Int? = nil, label: String? = nil) {
        mutate(label ?? "Restored \u{201c}\(displayName(of: note))\u{201d}") { list in
            var next = list
            next.removeAll { $0.id == note.id }
            if let index, index >= 0, index <= next.count {
                next.insert(note, at: index)
            } else {
                next.insert(note, at: 0)
            }
            return next
        }
    }

    func delete(ids: [UUID], label: String? = nil, offersUndo: Bool? = nil) {
        let targets = Set(ids)
        guard !targets.isEmpty else { return }
        let removed = notes.filter { targets.contains($0.id) }
        guard !removed.isEmpty else { return }
        mutate(label ?? (removed.count == 1
                         ? "Deleted \u{201c}\(displayName(of: removed[0]))\u{201d}"
                         : "Deleted \(removed.count) notes"),
               offersUndo: offersUndo) { list in
            list.filter { !targets.contains($0.id) }
        }
    }

    func deleteAll(label: String = "Deleted every note") {
        guard !notes.isEmpty else { return }
        mutate(label) { _ in [] }
    }

    /// Sets the whole list in one go - used by import and by undo-friendly bulk edits, so a
    /// 500-note import is one write and one Undo entry rather than 500 of each.
    func replaceAll(_ newNotes: [Note], label: String) {
        mutate(label) { _ in newNotes }
    }

    /// Reminders are a state, not an edit: ticking one should not reorder the list by "last edited",
    /// but it must still be undoable, so it goes through the same path.
    func setReminderCompleted(_ completed: Bool, for id: UUID) {
        mutate(completed ? "Marked a reminder done" : "Reopened a reminder") { list in
            var next = list
            guard let index = next.firstIndex(where: { $0.id == id }) else { return list }
            next[index].isReminderCompleted = completed
            return next
        }
    }

    // MARK: - Undo

    /// Undoes the last recorded change, whatever it was.
    @discardableResult
    func undoLastChange() -> String? {
        guard let last = undoStack.popLast() else { return nil }
        // Assigning directly (not through mutate) keeps undo out of its own stack, so one tap goes
        // back one step rather than bouncing between two states.
        notes = last.notes
        undoLabel = undoStack.last?.label
        // Putting something back does not need an offer to undo the undo.
        undoOfferVisible = false
        undoGeneration += 1
        return last.label
    }

    private func mutate(_ label: String?, offersUndo: Bool? = nil, _ change: ([Note]) -> [Note]) {
        let previous = notes
        let next = change(previous)
        guard next != previous else { return }
        undoStack.append((label ?? "Changed a note", previous))
        if undoStack.count > undoDepth { undoStack.removeFirst() }
        undoLabel = label ?? "Changed a note"
        // The banner is for the one case where you cannot put it right yourself: notes that are gone.
        // Ticking a reminder, saving what you typed, tagging, setting a date - all undoable by hand
        // in seconds, and a popup for each of them was noise that taught people to swipe it away
        // without reading, which is how a real "3 notes deleted, Undo?" gets missed.
        // Every change still lands on the undo stack, so the chat's own Undo chip works as before, and
        // a later change retires the banner rather than letting it nag about something already moved on
        // from: "Undo" offered next to an unrelated edit would undo the wrong thing.
        undoOfferVisible = offersUndo ?? (next.count < previous.count)
        undoGeneration += 1
        notes = next
    }

    private func displayName(of note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Set once when the saved list could not be read whole, so Settings and the first notice can
    /// say what happened instead of the app simply looking empty.
    @Published private(set) var recoveryNotice: String? = nil

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
            return
        }
        // One unreadable note used to cost the whole collection: the decode threw, `notes` stayed
        // empty, and the next write persisted an empty list over the top of everything. So the bad
        // copy is put aside first, then salvaged note by note.
        UserDefaults.standard.set(data, forKey: storageKey + "_unreadable_copy")
        var salvaged: [Note] = []
        var dropped = 0
        if let loose = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in loose {
                guard let entryData = try? JSONSerialization.data(withJSONObject: entry),
                      let note = try? JSONDecoder().decode(Note.self, from: entryData) else {
                    dropped += 1
                    continue
                }
                salvaged.append(note)
            }
        }
        notes = salvaged
        recoveryNotice = dropped > 0
            ? "Saved notes were damaged. \(salvaged.count) were recovered and \(dropped) could not be read; an untouched copy of the file is kept on the device."
            : "Saved notes were damaged but have all been recovered; an untouched copy is kept on the device."
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
            return "Writes a short answer, shows the note it came from, and can search or change things for you."
        case .jumpAndHighlight:
            return "Opens the matching note and marks the answer, offline. Ask it to change something and it still uses the AI for that."
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    /// A key with a stray space or newline from copy-paste used to fail as "check your connection",
    /// which is the least helpful thing this app could say. Trimmed on the way in, so what is stored
    /// is what was meant.
    var apiKey: String {
        get { deepSeekAPIKey }
        set { deepSeekAPIKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @Published var answerMode: AnswerMode {
        didSet {
            UserDefaults.standard.set(answerMode.rawValue, forKey: storageKey)
        }
    }

    @Published var deepSeekAPIKey: String {
        didSet {
            let cleaned = deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned != deepSeekAPIKey {
                // Re-entering through the same property keeps one write path and one publisher.
                deepSeekAPIKey = cleaned
                return
            }
            UserDefaults.standard.set(cleaned, forKey: apiKeyStorageKey)
        }
    }

    /// Kept so the Ask tab can tell "no key" apart from "key is set but the last call failed",
    /// instead of showing a spinner that never resolves.
    @Published var lastAIError: String? = nil

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

extension QuestionAnswerer {
    /// Verbs that only *look* like orders. "find", "show", "list" and friends are how people ask a
    /// question of their own notes, so in the offline mode they must not be sent to the AI.
    static let changeVerbs: Set<String> = [
        "add", "create", "make", "write", "new", "delete", "remove", "trash", "erase", "clear",
        "change", "edit", "update", "fix", "correct", "rename", "append", "set", "remind",
        "categorize", "categorise", "tag", "untag", "undo", "move", "switch", "turn", "enable",
        "disable", "duplicate", "merge", "mark", "put", "note", "remember", "log", "record",
        "increase", "decrease", "replace",
    ]

    /// True when the message wants a note created, changed, deleted, or the app itself moved -
    /// which is to say: when the offline matcher genuinely cannot serve it.
    static func wantsAChange(_ text: String) -> Bool {
        let words = tokenize(text)
        guard !words.isEmpty else { return false }
        if changeVerbs.contains(words[0]) { return true }
        return words.filter { changeVerbs.contains($0) }.count >= 2
    }
}

// MARK: - Notes list

struct NotesListView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var didTapAdd = false

    private var visibleNotes: [Note] {
        notesStore.visibleNotes(search: coordinator.searchText, category: coordinator.categoryFilter)
    }

    /// Ids only. Animating on the notes themselves made every keystroke and every reminder tick
    /// re-fade the whole list, because a note is Equatable across its text, dates and flags.
    private var visibleIDs: [UUID] { visibleNotes.map { $0.id } }

    private var availableCategories: [String] { notesStore.allCategories }

    private var tiers: [UUID: ReminderTier] { notesStore.reminderTiers() }

    private var isFiltered: Bool {
        coordinator.categoryFilter != nil
            || !coordinator.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $coordinator.notesPath) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    if !availableCategories.isEmpty {
                        CategoryChipsRow(categories: availableCategories,
                                         selection: $coordinator.categoryFilter,
                                         allLabel: "All Notes")
                    }

                    Group {
                        if notesStore.notes.isEmpty {
                            ContentUnavailableView {
                                Label("No Notes Yet", systemImage: "note.text")
                            } description: {
                                Text("Tap the + button to write one, or ask the assistant in the Ask tab to make one for you.")
                            }
                        } else if visibleNotes.isEmpty {
                            emptyFilterState
                        } else {
                            notesList
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Always visible — previously this hid whenever the notes list
                // was empty, even though the empty-state message told people to
                // "tap the button below" to create their first note.
                Button(action: addNewNote) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(settings.theme.gradient, in: Circle())
                        .shadow(color: settings.theme.endColor.opacity(0.45), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .sensoryFeedback(.impact(weight: .medium), trigger: didTapAdd)
            }
            .background(AmbientBackground())
            .navigationTitle("Notes")
            // The search field and the category chip live on the coordinator, not in here, so the
            // assistant can clear them, set them, or tell the user they are hiding the note it just
            // added - previously nothing outside this tab could even see that a filter was on.
            .searchable(text: $coordinator.searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        coordinator.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(settings.theme.gradient, in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }
                if isFiltered {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Show all") {
                            withAnimation(.snappy) { coordinator.clearFilters() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $coordinator.showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: NoteRoute.self) { route in
                NoteDetailView(route: route)
            }
            .onChange(of: notesStore.revision) { _, _ in
                dropFilterThatNoLongerApplies()
            }
        }
    }

    private var notesList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(visibleNotes) { note in
                    // The row is a tap gesture, not a NavigationLink, and that is the whole reason the
                    // bell can be pressed: a Button nested inside a NavigationLink's label never gets
                    // its tap, which is why ticking a reminder from the Notes tab did nothing at all.
                    NoteRowView(note: note, tier: tiers[note.id]) {
                        toggleReminder(on: note)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) {
                            coordinator.notesPath.append(NoteRoute(noteID: note.id))
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .id(note.id)
                    .flashWhenRecentlyChanged(note.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            // No withAnimation here: the list already animates on its visible ids, and
                            // wrapping the store change as well made the row flash and snap back.
                            notesStore.delete(ids: [note.id])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.snappy, value: visibleIDs)
            .onChange(of: coordinator.scrollRequest) { _, target in
                guard let target else { return }
                let id = target.noteID
                // Two passes: the row may not be laid out yet when the list has just had a filter
                // cleared, and a single scrollTo then lands in the middle of the previous position.
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 240_000_000)
                    proxy.scrollTo(id, anchor: .center)
                    // Only clear this request; a newer one must survive (the nonce is what makes a
                    // repeat of the same note count as a new request at all).
                    if coordinator.scrollRequest?.nonce == target.nonce { coordinator.scrollRequest = nil }
                }
            }
        }
    }

    /// The old single message said "no results for your search" when the search box was empty and a
    /// category chip was responsible - so the fix looked like searching differently.
    @ViewBuilder
    private var emptyFilterState: some View {
        if let category = coordinator.categoryFilter {
            ContentUnavailableView {
                Label("Nothing in “\(category)”", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No note is tagged \(category) right now.")
            } actions: {
                Button("Show all notes", action: coordinator.clearFilters)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView.search(text: coordinator.searchText)
        }
    }

    private func addNewNote() {
        didTapAdd.toggle()
        let note = Note(title: "", body: "")
        notesStore.add(note, label: "Started a new note")
        coordinator.reveal(noteID: note.id, in: notesStore, startEditing: true, isFresh: true)
    }

    private func toggleReminder(on note: Note) {
        guard note.reminderDate != nil else { return }
        // Ticking a reminder is not an edit, so it deliberately does not bump dateModified - but it
        // still goes through the store, which means the Undo bar appears and the Date tab agrees
        // immediately instead of waiting for a tab switch.
        notesStore.setReminderCompleted(!note.isReminderCompleted, for: note.id)
        coordinator.markChanged([note.id])
    }

    private func dropFilterThatNoLongerApplies() {
        guard let category = coordinator.categoryFilter else { return }
        guard !availableCategories.contains(category) else { return }
        coordinator.categoryFilter = nil
        coordinator.say("Left “\(category)” because no notes are in it any more.")
    }
}

struct NoteRowView: View {
    @EnvironmentObject var settings: SettingsStore
    let note: Note
    /// The reminder's rank among everything the user is waiting on. Nil when the note has no date.
    var tier: ReminderTier? = nil
    /// Ticking a reminder used to be decoration here - the bell could not be tapped, and the Date
    /// tab was the only place that could change it, while the Notes tab was the only place that
    /// could delete. Both tabs can now do both.
    var onToggleReminder: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let reminder = note.reminderDate {
                    Button(action: { onToggleReminder?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: note.isReminderCompleted ? "checkmark.circle.fill" : "bell.fill")
                                .font(.caption.weight(.semibold))
                            Text(rowDateFormatter.localizedString(for: reminder, relativeTo: Date()))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(rowColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(rowColor.opacity(0.13)))
                        .contentShape(Capsule())
                        // The colour follows the reminder, not the tab you happen to be on, so it
                        // settles into a shade instead of snapping when a tick changes the ranking.
                        .animation(.snappy(duration: 0.35), value: tier)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(note.isReminderCompleted ? "Reminder done, tap to open it again"
                                                                 : "Reminder \(relativeDateFormatter.localizedString(for: reminder, relativeTo: Date())), tap to mark done")
                }
            }

            Text(note.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if !note.categoryEnglish.isEmpty {
                    Text(note.categoryKurdish.isEmpty ? note.categoryEnglish : "\(note.categoryEnglish) · \(note.categoryKurdish)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(settings.theme.endColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(settings.theme.endColor)
                }

                Spacer(minLength: 0)

                Text(relativeDateFormatter.localizedString(for: note.dateModified, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Same rule as the Date tab - a past date and the nearest few are red, the next ones amber, the
    /// rest green, a finished reminder goes quiet. A note with no reminder date keeps the theme colour.
    private var rowColor: Color {
        tier?.color ?? settings.theme.endColor
    }

    /// "in 2 days" / "3 days ago" in the list, so a reminder's date is visible where the note is -
    /// previously only the Date tab knew when anything was due.
    private var rowDateFormatter: RelativeDateTimeFormatter { relativeDateFormatter }
}

// MARK: - Note detail / editor

struct NoteDetailView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    let route: NoteRoute

    private var noteID: UUID { route.noteID }
    private var highlight: String? { route.highlight }
    private var highlightLine: String? { route.highlightLine }
    private var startInEditMode: Bool { route.startEditing }
    private var highlightColor: Color { (route.theme ?? settings.theme).startColor }

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var didSave = false
    @State private var autoCategorizeTask: Task<Void, Never>? = nil
    @State private var focusTask: Task<Void, Never>? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, body
    }

    private var note: Note? { notesStore.note(id: noteID) }
    private var isDirty: Bool {
        guard let note else { return !draftTitle.isEmpty || !draftBody.isEmpty }
        return note.title != draftTitle || note.body != draftBody
    }

    var body: some View {
        Group {
            if let note {
                Group {
                    if isEditing {
                        editingView(note: note)
                    } else {
                        readingView(note: note)
                    }
                }
                .background(AmbientBackground())
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
                .onAppear { startIfAskedTo() }
                .onChange(of: coordinator.scrollRequest) { _, target in
                    guard target?.noteID == noteID else { return }
                    scrollToHighlight()
                }
            } else {
                missingNoteView
            }
        }
        .onDisappear { tidyUpOnLeaving() }
    }

    // MARK: - Reading

    private func readingView(note: Note) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        // A value found in the title used to highlight nothing at all, because only
                        // the body was searched. The title gets the same marker now.
                        titleWithHighlightIfNeeded(note: note)
                            .fixedSize(horizontal: false, vertical: true)

                        if !note.categoryEnglish.isEmpty {
                            Text(note.categoryKurdish.isEmpty ? note.categoryEnglish : "\(note.categoryEnglish) · \(note.categoryKurdish)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(settings.theme.endColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(settings.theme.endColor)
                        }
                    }

                    Text(highlightedBody(in: note))
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(Self.highlightAnchor)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Created \(absoluteDateFormatter.string(from: note.dateCreated))", systemImage: "calendar")
                        Label("Edited \(relativeDateFormatter.localizedString(for: note.dateModified, relativeTo: Date()))", systemImage: "clock")
                        if let reminder = note.reminderDate {
                            Label(reminderLabel(reminder), systemImage: note.isReminderCompleted ? "checkmark.circle" : "bell.badge")
                                .foregroundStyle(note.isReminderCompleted ? Color.secondary : Color(red: 1.0, green: 0.23, blue: 0.19))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground(cornerRadius: 16)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                highlightProxy = proxy
                scrollToHighlight()
            }
        }
    }

    /// "Jump & Highlight" used to jump and not scroll: when the answer sat below the fold the
    /// highlight existed and nobody could see it, which read as "the highlight didn't work".
    private func scrollToHighlight() {
        guard !isEditing, highlight?.isEmpty == false else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.snappy) {
                proxyForHighlight?.scrollTo(Self.highlightAnchor, anchor: .center)
            }
        }
    }

    /// The scroll proxy is only available inside the ScrollViewReader, so it is parked here for the
    /// coordinator-driven scroll that can arrive later.
    private var proxyForHighlight: ScrollViewProxy? { highlightProxy }

    private static let highlightAnchor = "note-highlight-anchor"

    private func reminderLabel(_ reminder: Date) -> String {
        let prefix = reminder < Date() ? "Reminder was \(relativeDateFormatter.localizedString(for: reminder, relativeTo: Date()))"
                                      : "Reminder \(relativeDateFormatter.localizedString(for: reminder, relativeTo: Date()))"
        return note?.isReminderCompleted == true ? prefix + " · done" : prefix
    }

    @ViewBuilder
    private func titleWithHighlightIfNeeded(note: Note) -> some View {
        let title = note.title.isEmpty ? "Untitled" : note.title
        let base = Text(title)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
        if let highlight, !highlight.isEmpty, title.range(of: highlight, options: [.caseInsensitive]) != nil {
            base
                .padding(4)
                .background(highlightColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.primary)
        } else {
            base
                .foregroundStyle(.primary)
        }
    }

    private func highlightedBody(in note: Note) -> AttributedString {
        guard let needle = highlight, !needle.isEmpty else { return AttributedString(note.body) }
        guard let range = highlightRange(needle: needle, in: note.body) else {
            return AttributedString(note.body)
        }
        let prefix = String(note.body[note.body.startIndex..<range.lowerBound])
        let match = String(note.body[range])
        let suffix = String(note.body[range.upperBound...])

        var marked = AttributedString(match)
        marked.backgroundColor = highlightColor.opacity(0.45)
        marked.foregroundColor = .primary
        return AttributedString(prefix) + marked + AttributedString(suffix)
    }

    /// Prefers the occurrence on the line the answer actually came from. Searching the whole body for
    /// "10" highlighted a date at the top of the note instead of the price the question asked about.
    private func highlightRange(needle: String, in body: String) -> Range<String.Index>? {
        if let line = highlightLine, !line.isEmpty,
           let lineRange = body.range(of: line, options: [.caseInsensitive]) {
            let lineText = String(body[lineRange])
            if let inner = lineText.range(of: needle, options: [.caseInsensitive]) {
                // Both ends are measured the same way. Using `needle.count` for the far end - which
                // is what happened - assumes the match is exactly as long as the needle, and a
                // case-insensitive match in Turkish or German can be a character or two longer,
                // which then reaches past the line for the highlight.
                let start = body.index(lineRange.lowerBound, offsetBy: lineText.distance(from: lineText.startIndex, to: inner.lowerBound))
                let end = body.index(lineRange.lowerBound, offsetBy: lineText.distance(from: lineText.startIndex, to: inner.upperBound))
                return start..<end
            }
            if let loose = looseRange(of: needle, in: lineText) {
                let start = body.index(lineRange.lowerBound, offsetBy: lineText.distance(from: lineText.startIndex, to: loose.lowerBound))
                return start..<body.index(start, offsetBy: lineText.distance(from: loose.lowerBound, to: loose.upperBound))
            }
        }
        if let direct = body.range(of: needle, options: [.caseInsensitive]) { return direct }
        return looseRange(of: needle, in: body)
    }

    /// Matched on letters and digits only, so "$20" still finds "20 $" and a value the model tidied
    /// up slightly still gets marked rather than silently not.
    private func looseRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        let target = Array(needle.lowercased().filter { $0.isLetter || $0.isNumber })
        guard !target.isEmpty else { return nil }
        var characters: [Character] = []
        var indexes: [String.Index] = []
        for index in haystack.indices {
            let character = haystack[index]
            if character.isLetter || character.isNumber {
                characters.append(Character(character.lowercased()))
                indexes.append(index)
            }
        }
        guard characters.count >= target.count else { return nil }
        for start in 0...(characters.count - target.count) {
            if Array(characters[start..<start + target.count]) == target {
                let last = start + target.count - 1
                return indexes[start]..<haystack.index(after: indexes[last])
            }
        }
        return nil
    }

    // MARK: - Editing

    private func editingView(note: Note) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draftTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .body }
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // A soft fading gradient instead of a hard system Divider - feels less
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

            if isDirty {
                HStack(spacing: 8) {
                    Circle().fill(settings.theme.endColor).frame(width: 7, height: 7)
                    Text("Unsaved — leaving saves it")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Save now") { saveDraft(originalNote: note) }
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .onChange(of: draftTitle) { _, _ in scheduleAutoCategorize() }
        .onChange(of: draftBody) { _, _ in scheduleAutoCategorize() }
    }

    private func startIfAskedTo() {
        guard startInEditMode, !isEditing else { return }
        if let note {
            draftTitle = note.title
            draftBody = note.body
        }
        isEditing = true
        // Cancelled when the screen goes away. The old fixed 0.35s timer fired whatever had
        // happened in between, so leaving quickly could raise the keyboard over the previous screen -
        // and on a slower phone it missed the transition instead.
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled, isEditing else { return }
            focusedField = .title
        }
    }

    private func handleToolbarTap(note: Note) {
        if isEditing {
            saveDraft(originalNote: note)
            focusedField = nil
            didSave.toggle()
            // The keyboard is dismissed first and the layout swapped a frame later, so the two
            // animations stop competing for the same space and jumping.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.snappy) { isEditing = false }
            }
        } else {
            draftTitle = note.title
            draftBody = note.body
            withAnimation(.snappy) { isEditing = true }
            focusedField = .title
        }
    }

    private func tidyUpOnLeaving() {
        focusTask?.cancel()
        autoCategorizeTask?.cancel()
        guard isEditing else { return }
        let emptyDraft = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if emptyDraft {
            // Backing out of a brand-new note must not leave a blank "Untitled" behind - but only of
            // one the + button just made. This used to fire for any note opened in edit mode, so an
            // existing note that happened to be empty was deleted underneath the user.
            // Nothing was lost, so nothing is announced: this note never had any content.
            if route.isFresh { notesStore.delete(ids: [noteID], label: "Discarded the empty note", offersUndo: false) }
            return
        }
        // Saving on the way out. Losing typed text because Back was pressed instead of Save is the
        // same class of failure as the assistant losing part of a note: the work is gone and nothing
        // said so.
        if isDirty {
            var updated = note ?? Note(title: draftTitle, body: draftBody)
            updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : draftTitle
            updated.body = draftBody
            updated.dateModified = Date()
            if note == nil {
                notesStore.add(updated, label: "Kept the note you typed")
            } else {
                notesStore.update(updated, label: "Saved “\(displayName(of: updated))”")
            }
        }
    }

    private func saveDraft(originalNote: Note) {
        var updated = originalNote
        updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : draftTitle
        updated.body = draftBody
        updated.dateModified = Date()
        notesStore.update(updated, label: "Saved “\(displayName(of: updated))”")
    }

    private func displayName(of note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }

    /// While the user writes, wait for a pause and have the model suggest a bilingual category - but
    /// only when one is not already set and a key exists. Runs on the main actor: `notes` must not be
    /// touched from a background thread, which is how a list could end up not repainting.
    private func scheduleAutoCategorize() {
        guard !settings.deepSeekAPIKey.isEmpty else { return }
        autoCategorizeTask?.cancel()

        let titleSnapshot = draftTitle
        let bodySnapshot = draftBody
        let targetID = noteID

        autoCategorizeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            guard let current = notesStore.note(id: targetID), current.categoryEnglish.isEmpty else { return }
            guard let result = await OnlineAI.suggestCategory(title: titleSnapshot, body: bodySnapshot, apiKey: settings.deepSeekAPIKey) else { return }
            guard !Task.isCancelled else { return }

            // Re-fetch rather than reusing `current`, so a category set in between is not clobbered.
            guard var latest = notesStore.note(id: targetID), latest.categoryEnglish.isEmpty else { return }
            latest.categoryEnglish = result.en
            latest.categoryKurdish = result.ku
            notesStore.update(latest, label: "Tagged “\(latest.title.isEmpty ? "Untitled" : latest.title)” as \(result.en)")
        }
    }

    // MARK: - The note is gone

    private var missingNoteView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("This note was deleted", systemImage: "trash.slash")
            } description: {
                Text("It was removed while this screen was open — by a swipe, the assistant, or an import.")
            } actions: {
                HStack(spacing: 10) {
                    if notesStore.canUndo {
                        Button("Undo the delete") {
                            if let label = notesStore.undoLastChange() {
                                coordinator.say("Undid: \(label)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !draftBody.isEmpty || !draftTitle.isEmpty {
                        Button("Keep what you typed as a new note") {
                            var note = Note(title: draftTitle, body: draftBody)
                            note.dateModified = Date()
                            notesStore.add(note, label: "Kept the text you had typed")
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Close", action: { dismiss() })
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .background(AmbientBackground())
    }

    /// Parking the proxy lets a scroll request from another tab work after this screen appears.
    @State private var highlightProxy: ScrollViewProxy? = nil
}

// MARK: - Ask tab (chat-style)

/// A note the assistant touched, so its reply can offer to open it.
struct OpenedNote: Equatable {
    var id: UUID
    var title: String
}

enum ConfirmationAnswer: Equatable {
    case approved(String)
    case declined
    case superseded
}

// MARK: - Chat pieces

/// A note the answer came from, shown as a tappable chip above the reply.
struct SourceNoteChip: Identifiable, Equatable {
    let id: UUID // the note's own id
    let title: String
    let theme: AppTheme
}

/// One piece of an answer, optionally tied to a source note (and colored to match its chip).
struct ResolvedAnswerSegment: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var noteID: UUID?
    var excerpt: String?
    var theme: AppTheme?
    var isValue: Bool = false
}

struct ChatBubbleUser: View {
    @EnvironmentObject var settings: SettingsStore
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 6, topTrailing: 20),
                        style: .continuous
                    )
                    .fill(settings.theme.gradient)
                    .shadow(color: settings.theme.endColor.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .textSelection(.enabled)
        }
    }
}

struct ChatBubbleAssistantPlain: View {
    let text: String
    /// A refusal or a failure is drawn differently on purpose. Everything used to look like an
    /// answer, which is how "I can't do that in this app" and "here is your note" read the same.
    var tinted = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if tinted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 20, bottomLeading: 6, bottomTrailing: 20, topTrailing: 20),
                        style: .continuous
                    )
                    .fill(tinted ? Color.orange.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
                }
                .textSelection(.enabled)
            Spacer(minLength: 24)
        }
    }
}

/// A clean, themed box for a copyable answer value (password, code, price, etc.) with a tap-to-copy icon.
struct ValueCopyChip: View {
    let text: String
    let theme: AppTheme
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(.snappy) { didCopy = true }
            // Restarting the timer rather than stacking a second one: with two taps, the first
            // task cleared the tick while you were still looking at it.
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { didCopy = false }
            }
        } label: {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: theme.endColor.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case userQuestion(String)
        case answerCard(AnswerResult)
        case plainText(String)
        /// The "thinking" state as its own case. It used to be spotted by comparing the bubble's text
        /// with the literal word "Thinking…", so a reply that happened to start with that word looked
        /// like a request that would never finish.
        case waiting
        /// `undoGeneration` is the store's counter at the moment this bubble's change was applied.
        /// Undo is offered only while that is still the newest change - matching on the label instead
        /// would be fooled by two changes that happen to have the same wording.
        case actionResult(text: String, opened: OpenedNote?, failed: Bool, undoGeneration: Int?)
        case confirmation(PendingConfirmation, answered: ConfirmationAnswer?)
        case sourcedAnswer(chips: [SourceNoteChip], segments: [ResolvedAnswerSegment])
    }

    var id: UUID = UUID()
    let kind: Kind
}

struct AskView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var questionText = ""
    @State private var messages: [ChatMessage] = []
    @State private var conversationHistory: [ConversationTurn] = []
    @State private var didAsk = false
    @State private var isWaiting = false
    @State private var requestTask: Task<Void, Never>?
    /// Bumped whenever a request becomes irrelevant. Late answers used to be applied no matter what
    /// had happened meanwhile - so a note could appear after the chat had been cleared.
    @State private var generation = 0
    @State private var scrollTargetID: UUID?
    @FocusState private var isInputFocused: Bool

    private let suggestions = [
        "How much did the restaurant cost?",
        "Find a password in my notes",
        "Create a new note for me",
        "Remind me about my electricity bill tomorrow at 9"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        chatScrollView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                inputBar
            }
            .background(AmbientBackground())
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !messages.isEmpty {
                        Button(role: .destructive) { clearChat() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("New chat")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: didAsk)
            .onAppear { takeDraft() }
            .onChange(of: coordinator.askDraft) { _, _ in takeDraft() }
        }
    }

    private func takeDraft() {
        guard let draft = coordinator.askDraft else { return }
        questionText = draft
        coordinator.askDraft = nil
        isInputFocused = true
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(settings.theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: settings.theme.endColor.opacity(0.4), radius: 18, x: 0, y: 10)

            Text("Ask your notes")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Get quick answers pulled straight from what you've written.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if settings.deepSeekAPIKey.isEmpty {
                Button {
                    coordinator.showingSettings = true
                } label: {
                    Label("Add your Gemini key in Settings", systemImage: "key.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            if settings.answerMode == .jumpAndHighlight {
                // Jump & Highlight is the offline mode; it no longer swallows requests that want
                // something done, but the difference is worth stating once, plainly.
                Label("Jump & Highlight mode: answers come from your own notes, offline. Changes still ask for your key.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        questionText = suggestion
                        isInputFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat

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
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // The answer *replaces* the waiting bubble, so the count does not change and the old
            // trigger left the finished answer below the fold. Watching the last id covers both.
            .onChange(of: scrollTargetID) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
                scrollTargetID = nil
            }
            .onChange(of: scrollToken) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.snappy) { proxy.scrollTo(lastID, anchor: .bottom) }
                // Second pass once the new bubble has been laid out - a single scrollTo measures the
                // old content and lands mid-conversation.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var scrollToken: String { "\(messages.count):\(messages.last?.id.uuidString ?? "-")" }

    @ViewBuilder
    private func messageView(for message: ChatMessage) -> some View {
        switch message.kind {
        case .userQuestion(let text):
            ChatBubbleUser(text: text)

        case .answerCard(let result):
            HStack(alignment: .top, spacing: 0) {
                AnswerCardView(result: result) {
                    let opened = coordinator.reveal(noteID: result.matchedNote.id,
                                                    in: notesStore,
                                                    highlight: result.extractedAnswer,
                                                    highlightLine: result.matchedLine)
                    if !opened { coordinator.say("That note was deleted, so there's nothing to open.") }
                }
                .frame(maxWidth: 320, alignment: .leading)
                Spacer(minLength: 24)
            }

        case .waiting:
            TypingIndicator(onStop: { cancelRequest() })

        case .plainText(let text):
            ChatBubbleAssistantPlain(text: text)

        case .actionResult(let text, let opened, let failed, let undoGeneration):
            VStack(alignment: .leading, spacing: 6) {
                ChatBubbleAssistantPlain(text: text, tinted: failed)
                HStack(spacing: 10) {
                    if let opened {
                        Button {
                            if !coordinator.reveal(noteID: opened.id, in: notesStore) {
                                coordinator.say("That note isn't in the list any more.")
                            }
                        } label: {
                            Label("Open “\(opened.title)”", systemImage: "arrow.right.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let undoGeneration, notesStore.undoGeneration == undoGeneration {
                        Button {
                            if let label = notesStore.undoLastChange() {
                                coordinator.say("Undid: \(label)")
                                withAnimation(.snappy) {
                                    if let index = messages.firstIndex(where: { $0.id == message.id }) {
                                        messages[index] = ChatMessage(id: message.id, kind: .plainText("Undone — \(label)."))
                                    }
                                }
                            }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer(minLength: 24)
                }
            }

        case .confirmation(let pending, let answered):
            confirmationCard(pending: pending, answered: answered, messageID: message.id)

        case .sourcedAnswer(let chips, let segments):
            sourcedAnswerView(chips: chips, segments: segments)
        }
    }

    @ViewBuilder
    private func sourcedAnswerView(chips: [SourceNoteChip], segments: [ResolvedAnswerSegment]) -> some View {
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
                                    .shadow(color: chip.theme.endColor.opacity(0.35), radius: 6, x: 0, y: 3)
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
                    .padding(.vertical, 11)
                    .background {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 20, bottomLeading: 6, bottomTrailing: 20, topTrailing: 20),
                            style: .continuous
                        )
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
                    }
                    .textSelection(.enabled)
                Spacer(minLength: 24)
            }

            let valueSegments = segments.filter { $0.isValue }
            if !valueSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(valueSegments) { segment in
                        ValueCopyChip(text: segment.text, theme: segment.theme ?? settings.theme)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func confirmationCard(pending: PendingConfirmation,
                                  answered: ConfirmationAnswer?,
                                  messageID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatBubbleAssistantPlain(text: pending.question)
            Text(pending.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            if pending.noteTitles.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(pending.noteTitles, id: \.self) { title in
                        Label(title, systemImage: "note.text")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            switch answered {
            case .approved(let text):
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            case .declined:
                Label("Kept. Nothing was changed.", systemImage: "xmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .superseded:
                Label("Not acted on — this request was replaced by a newer one.", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case nil:
                HStack(spacing: 10) {
                    Button(pending.isDestructive ? "Delete" : "Do it") {
                        confirm(pending, messageID: messageID)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pending.isDestructive ? .red : settings.theme.endColor)
                    .controlSize(.small)

                    Button("Keep it") {
                        decline(confirmation: pending, messageID: messageID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("or just type “yes”")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                }
            }
        }
    }

    /// Approving a card - by button or by typing "yes" - goes through here, so a typed answer closes
    /// the card too. Answering "yes" in words used to leave the "Do it" button live, and tapping it a
    /// second later applied the same change twice: a double delete, or two identical notes.
    private func confirm(_ pending: PendingConfirmation, messageID: UUID?) {
        let text = AIActions.confirm(pending, in: notesStore, coordinator: coordinator)
        answer(pending: pending, messageID: messageID, with: .approved(text), spoken: text)
        conversationHistory.append(ConversationTurn(role: "model", text: "[done] user confirmed this change: \(pending.question)"))
    }

    private func decline(confirmation pending: PendingConfirmation, messageID: UUID?) {
        coordinator.pendingConfirmation = nil
        let text = AIActions.decline(pending)
        answer(pending: pending, messageID: messageID, with: .declined, spoken: text)
        conversationHistory.append(ConversationTurn(role: "model", text: "[declined] the user said no; nothing changed"))
    }

    /// Writes the answer onto the card that asked. `messageID` is nil when the card was answered from
    /// the input field, so the card is found by the confirmation's own id instead.
    private func answer(pending: PendingConfirmation,
                        messageID: UUID?,
                        with answerValue: ConfirmationAnswer,
                        spoken: String) {
        let index = messageID.flatMap { id in messages.firstIndex(where: { $0.id == id }) }
            ?? messages.lastIndex(where: {
                if case .confirmation(let candidate, let answered) = $0.kind { return candidate.id == pending.id && answered == nil }
                return false
            })
        withAnimation(.snappy) {
            guard let index, case .confirmation(let candidate, _) = messages[index].kind else {
                messages.append(ChatMessage(kind: .plainText(spoken)))
                return
            }
            messages[index] = ChatMessage(id: messages[index].id, kind: .confirmation(candidate, answered: answerValue))
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
        // A chip whose note has since been deleted used to push a screen reading "Note Not Found".
        guard coordinator.reveal(noteID: chip.id, in: notesStore,
                                 highlight: excerpt,
                                 highlightLine: excerpt,
                                 theme: chip.theme) else {
            coordinator.say("“\(chip.title)” isn't in your notes any more.")
            return
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = settings.lastAIError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button {
                        settings.lastAIError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }

            if let pending = coordinator.pendingConfirmation {
                Button {
                    coordinator.selectedTab = .ask
                    if let index = messages.lastIndex(where: {
                        if case .confirmation(let candidate, let answered) = $0.kind { return candidate.id == pending.id && answered == nil }
                        return false
                    }) {
                        withAnimation(.snappy) { scrollTargetID = messages[index].id }
                    }
                } label: {
                    Label("A change is waiting for you: \(pending.question)", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(settings.theme.endColor.opacity(0.16)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask something…", text: $questionText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendQuestion)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(settings.theme.gradient, lineWidth: 1.5)
                            .opacity(isInputFocused ? 1 : 0)
                            .animation(.snappy, value: isInputFocused)
                    }

                Button(action: sendQuestion) {
                    if isWaiting {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 38, height: 38)
                            .background(settings.theme.gradient, in: Circle())
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(settings.theme.gradient, in: Circle())
                            .shadow(color: settings.theme.endColor.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isWaiting || questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(isWaiting || questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    /// Resigns the on-screen keyboard. Clears the FocusState binding and also
    /// forces first-responder resignation as a safety net, since a vertical-axis
    /// TextField can occasionally ignore the FocusState change on its own.
    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func clearChat() {
        cancelRequest(quietly: true)
        withAnimation(.snappy) {
            messages.removeAll()
        }
        // The bubbles and the memory are the same thing to the assistant: clearing one and leaving the
        // other is how a "new" chat kept answering as if it had never been reset.
        conversationHistory = []
        settings.lastAIError = nil
        if let pending = coordinator.pendingConfirmation {
            coordinator.pendingConfirmation = nil
            supersede(pending: pending)
        }
        coordinator.say("Started a new chat.")
    }

    private func supersede(pending: PendingConfirmation) {
        withAnimation(.snappy) {
            if let index = messages.lastIndex(where: {
                if case .confirmation(let candidate, let answered) = $0.kind { return candidate.id == pending.id && answered == nil }
                return false
            }) {
                if case .confirmation(let candidate, _) = messages[index].kind {
                    messages[index] = ChatMessage(id: messages[index].id, kind: .confirmation(candidate, answered: .superseded))
                }
            }
        }
    }

    private func cancelRequest(quietly: Bool = false) {
        requestTask?.cancel()
        requestTask = nil
        generation += 1
        isWaiting = false
        guard !quietly else { return }
        if let index = messages.lastIndex(where: { if case .waiting = $0.kind { return true }; return false }) {
            withAnimation(.snappy) {
                messages[index] = ChatMessage(id: messages[index].id, kind: .plainText("Stopped — nothing was changed."))
            }
        }
    }

    // MARK: - Sending

    private func sendQuestion() {
        let trimmed = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismissKeyboard()
        didAsk.toggle()

        // A confirmation can be answered in words. Making someone find a small button inside an old
        // bubble, possibly on another tab, was how "yes I meant it" ended with nothing happening.
        if let pending = coordinator.pendingConfirmation {
            if AppCoordinator.isAffirmative(trimmed) {
                questionText = ""
                withAnimation(.snappy) { messages.append(ChatMessage(kind: .userQuestion(trimmed))) }
                confirm(pending, messageID: nil)
                return
            }
            if AppCoordinator.isNegative(trimmed) {
                questionText = ""
                withAnimation(.snappy) { messages.append(ChatMessage(kind: .userQuestion(trimmed))) }
                decline(confirmation: pending, messageID: nil)
                return
            }
        }

        questionText = ""
        withAnimation(.snappy) { messages.append(ChatMessage(kind: .userQuestion(trimmed))) }

        switch settings.answerMode {
        case .jumpAndHighlight:
            // Only a request that *changes* something needs the assistant. Routing "find my wifi
            // password" to the AI because it starts with "find" meant the offline mode asked for a
            // key for a question it could answer itself.
            if QuestionAnswerer.wantsAChange(trimmed) {
                if settings.deepSeekAPIKey.isEmpty {
                    appendPlainText("That needs the assistant, and there's no API key yet. Add one in Settings → AI Assistant, or do it by hand in the Notes tab.")
                } else {
                    runAI(question: trimmed)
                }
                return
            }
            jumpAndHighlightAnswer(for: trimmed)

        case .aiAnswer:
            runAI(question: trimmed)
        }
    }

    /// Jump & Highlight's own job: find the line locally, show the card, and open the note on the
    /// line - no network, no model, and now an actual highlight that is scrolled into view.
    private func jumpAndHighlightAnswer(for question: String) {
        guard let result = QuestionAnswerer.answer(for: question, in: notesStore.notes) else {
            appendPlainText("I couldn't find that in your notes. Try other words, or ask me to search the Notes tab — that runs the same search you'd type yourself.")
            return
        }
        withAnimation(.snappy) { messages.append(ChatMessage(kind: .answerCard(result))) }
        coordinator.reveal(noteID: result.matchedNote.id,
                           in: notesStore,
                           highlight: result.extractedAnswer,
                           highlightLine: result.matchedLine)
    }

    private func appendPlainText(_ text: String) {
        withAnimation(.snappy) { messages.append(ChatMessage(kind: .plainText(text))) }
    }

    private func runAI(question: String) {
        let waitingID = UUID()
        let myGeneration = generation + 1
        generation = myGeneration
        isWaiting = true
        withAnimation(.snappy) { messages.append(ChatMessage(id: waitingID, kind: .waiting)) }

        // Snapshotted before the Task so the prompt is built from one consistent set of notes.
        let allNotes = notesStore.notes
        let historySnapshot = conversationHistory
        let store = notesStore
        let appSettings = settings
        let coordinator = self.coordinator

        requestTask = Task { @MainActor in
            let outcome = await OnlineAI.answer(question: question,
                                               relevantNotes: allNotes,
                                               apiKey: appSettings.deepSeekAPIKey,
                                               history: historySnapshot,
                                               notePattern: appSettings.notePattern)
            // Anything that happened while we were away - the chat cleared, a newer question asked,
            // the request stopped - means this result is no longer wanted, applied *or* shown.
            guard !Task.isCancelled, generation == myGeneration else { return }
            isWaiting = false
            requestTask = nil

            let replyText: String
            let parsed: AIActionResponse
            switch outcome {
            case .failure(let failure):
                appSettings.lastAIError = failure.message
                replace(waitingID: waitingID, with: ChatMessage(kind: .plainText(failure.message)))
                conversationHistory.append(ConversationTurn(role: "user", text: question))
                conversationHistory.append(ConversationTurn(role: "model", text: "[failed] \(failure.message)"))
                trimHistory()
                return
            case .reply(let raw):
                parsed = AIProtocol.parse(raw)
                replyText = parsed.reply
            }

            var result = AIActions.apply(parsed,
                                       question: question,
                                       in: store,
                                       settings: appSettings,
                                       coordinator: coordinator)

            if parsed.malformed {
                result.reply = "I couldn't read my own answer just now, so I did nothing. Say that again and I'll try once more."
                result.isFailure = true
            }

            if let confirmation = result.confirmation {
                // A card the user walked past is answered, not left waiting: two live cards for one
                // question is how an old delete got applied after a newer request.
                if let stale = coordinator.pendingConfirmation, stale.id != confirmation.id {
                    supersede(pending: stale)
                }
                coordinator.pendingConfirmation = confirmation
                replace(waitingID: waitingID, with: ChatMessage(id: waitingID, kind: .confirmation(confirmation, answered: nil)))
            } else if parsed.action == "none", !parsed.segments.isEmpty,
                      let sourced = buildSourcedAnswerKind(parsed: parsed, replyText: result.reply) {
                replace(waitingID: waitingID, with: ChatMessage(id: waitingID, kind: sourced))
            } else {
                let opened = result.openableID.map { OpenedNote(id: $0, title: result.openableTitle ?? "note") }
                replace(waitingID: waitingID, with: ChatMessage(id: waitingID,
                                                                kind: .actionResult(text: result.reply,
                                                                                    opened: opened,
                                                                                    failed: result.isFailure,
                                                                                    undoGeneration: notesStore.undoGeneration)))
            }
            if let pending = result.confirmation {
                conversationHistory.append(ConversationTurn(role: "model", text: pending.question))
            }

            // The outcome, not just the sentence: this is what stops the assistant claiming a note
            // does not exist one turn after creating it.
            conversationHistory.append(ConversationTurn(role: "user", text: question))
            var modelLine = replyText
            if let outcomeForHistory = result.outcomeForHistory { modelLine += "\n" + outcomeForHistory }
            conversationHistory.append(ConversationTurn(role: "model", text: modelLine))
            trimHistory()
            appSettings.lastAIError = nil
        }
    }

    private func trimHistory() {
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }
    }

    private func replace(waitingID: UUID, with message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == waitingID }) else {
            withAnimation(.snappy) { messages.append(message) }
            return
        }
        withAnimation(.snappy) { messages[index] = message }
    }

    /// Builds the colored, source-attributed answer. Returns nil (plain text) when the segments do
    /// not hold up, so a slip by the model never breaks the answer itself.
    private func buildSourcedAnswerKind(parsed: AIActionResponse, replyText: String) -> ChatMessage.Kind? {
        guard !parsed.segments.isEmpty else { return nil }
        let reconstructedLength = parsed.segments.reduce(0) { $0 + $1.text.count }
        guard Double(reconstructedLength) >= Double(replyText.count) * 0.6 else { return nil }

        var seenTitles: [String] = []
        for segment in parsed.segments {
            if let title = segment.sourceNote, !title.isEmpty, !seenTitles.contains(title) {
                seenTitles.append(title)
            }
        }

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

        let resolvedSegments: [ResolvedAnswerSegment] = parsed.segments.compactMap { segment in
            guard !segment.text.isEmpty else { return nil }
            let noteID = segment.sourceNote.flatMap { titleToNoteID[$0] }
            let theme = segment.sourceNote.flatMap { titleToTheme[$0] } ?? (segment.isValue ? settings.theme : nil)
            let showTheme = (noteID != nil || segment.isValue) ? theme : nil
            return ResolvedAnswerSegment(text: segment.text, noteID: noteID, excerpt: segment.sourceExcerpt, theme: showTheme, isValue: segment.isValue)
        }
        guard !resolvedSegments.isEmpty else { return nil }
        guard !chips.isEmpty || resolvedSegments.contains(where: { $0.isValue }) else { return nil }
        return .sourcedAnswer(chips: chips, segments: resolvedSegments)
    }
}

struct AnswerCardView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var notesStore: NotesStore
    let result: AnswerResult
    let onTapNote: () -> Void

    /// The live note rather than the snapshot taken when the answer was produced, so a rename shows
    /// the new name and a deletion is admitted instead of pushing a screen saying "Note Not Found".
    private var live: Note? { notesStore.note(id: result.matchedNote.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(settings.theme.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Answer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(result.sentence)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTapNote) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundStyle(settings.theme.endColor)
                    Text(live.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "This note was deleted")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: live == nil ? "questionmark.circle" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardBackground()
        .opacity(live == nil ? 0.55 : 1)
    }
}

// MARK: - Settings tab

/// What the install is, straight from the bundle, so the footer can't disagree with the build
/// someone actually installed.
enum AppInfo {
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (build \(build))"
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.dismiss) private var dismiss

    private enum KeyTest: Equatable {
        case idle, testing, ok, failed(String)
    }

    private struct ImportPreview {
        var incoming: [Note]
        var newCount: Int
        var olderCount: Int
        var newerCount: Int
    }

    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var keyTest: KeyTest = .idle
    @State private var keyTestTask: Task<Void, Never>?
    @State private var showCapabilities = false
    @State private var importPreview: ImportPreview?
    @State private var statusMessage: String?
    @State private var exportURL: URL?
    @State private var showingClearAllConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    answeringStyleSection
                    aiAssistantSection
                    remindersSection
                    patternSection
                    themeSection
                    backupSection
                    dangerSection

                    // App version: edit or delete this one line to change/hide it.
                    Text(AppInfo.versionLine)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }
                .padding(20)
            }
            .background(AmbientBackground())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { keyDraft = settings.deepSeekAPIKey }
            // A result line that survives the sheet reads like last week's import.
            .onDisappear { statusMessage = nil }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
                inspectImport(result)
            }
            .confirmationDialog(importTitle, isPresented: Binding(
                get: { importPreview != nil },
                set: { if !$0 { importPreview = nil } }
            ), titleVisibility: .visible) {
                // The recommended choice first, and the one that overwrites your own newer work
                // marked destructive. The labels used to promise the opposite of what each button did.
                Button("Add \(importPreview?.newCount ?? 0) new, update \(importPreview?.newerCount ?? 0) newer from the file") {
                    applyImport(preferFile: false)
                }
                Button("Overwrite mine with the file", role: .destructive) {
                    applyImport(preferFile: true)
                }
                Button("Cancel", role: .cancel) { importPreview = nil }
            } message: {
                if let preview = importPreview {
                    Text("The file has \(preview.incoming.count) notes: \(preview.newCount) you don't have, \(preview.newerCount) newer than yours, \(preview.olderCount) older. Neither option deletes anything. \u{201c}Overwrite mine\u{201d} replaces your copy with the file's even where yours is newer - that's the one to avoid unless you mean it.")
                }
            }
            .confirmationDialog("Delete all \(notesStore.notes.count) notes?",
                                isPresented: $showingClearAllConfirm,
                                titleVisibility: .visible) {
                Button("Export first, then delete", role: .destructive) {
                    // Delete only once the file is provably on disk. "Exported, then deleted" used to
                    // be written before the write had even been attempted, so a failed export was a
                    // silent way to lose everything while being told the opposite.
                    guard prepareExport() else { return }
                    let count = notesStore.notes.count
                    notesStore.deleteAll(label: "Deleted all \(count) notes")
                    statusMessage = "Saved \(count) note(s) to Backup, then deleted them. Undo is in the bar above."
                }
                Button("Delete without exporting", role: .destructive) {
                    notesStore.deleteAll(label: "Deleted all \(notesStore.notes.count) notes")
                    coordinator.say("Deleted all \(notesStore.notes.count) notes.", actionLabel: "Undo", undoes: true)
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("The Undo bar brings them straight back; after you have edited something else, only a backup will.")
            }
        }
    }

    @State private var showingImporter = false

    // MARK: - Sections

    private var answeringStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Answering Style", systemImage: "sparkles")

            ForEach(AnswerMode.allCases) { mode in
                Button {
                    withAnimation(.snappy) { settings.answerMode = mode }
                    if mode == .jumpAndHighlight {
                        coordinator.say("Jump & Highlight answers offline; it still uses the assistant to change things.")
                    }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: mode == .aiAnswer ? "sparkles" : "arrow.right.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(settings.theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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

                        Image(systemName: settings.answerMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.answerMode == mode ? settings.theme.endColor : Color.secondary.opacity(0.35))
                            .font(.title3)
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
        }
    }

    private var aiAssistantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("AI Assistant", systemImage: "key.fill")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Group {
                        if revealKey {
                            TextField("Gemini API key", text: $keyDraft)
                        } else {
                            SecureField("Gemini API key", text: $keyDraft)
                        }
                    }
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: keyDraft) { _, newValue in
                        // Stored trimmed, so a space picked up while pasting cannot turn into
                        // "check your connection".
                        settings.deepSeekAPIKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        keyTest = .idle
                    }

                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                if settings.deepSeekAPIKey.isEmpty {
                    Label("No key set yet — answering and changes need one.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if OnlineAI.keyProblem(settings.deepSeekAPIKey) != nil {
                    Label("That doesn't look like a Gemini key: \(OnlineAI.keyProblem(settings.deepSeekAPIKey) ?? "").",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button {
                        testKey()
                    } label: {
                        HStack(spacing: 6) {
                            if case .testing = keyTest { ProgressView() }
                            Text(keyTest == .idle ? "Test key" : keyTestLabel)
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(settings.theme.endColor.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.deepSeekAPIKey.isEmpty || isTestingKey)

                    Spacer()
                }

                if case .failed(let message) = keyTest {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup("What the assistant can and can't do", isExpanded: $showCapabilities) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(AIProtocol.capabilityList, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(settings.theme.endColor)
                                    .padding(.top, 2)
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Anything not on this list it genuinely cannot do — it should tell you so rather than pretend. If it claims otherwise, that's a bug worth reporting.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(.leading, 4)
                    .animation(.snappy, value: showCapabilities)
                }
                .font(.caption.weight(.semibold))

                Text("Answers run through your own free Gemini key (aistudio.google.com/apikey) over the internet. The free tier is rate-limited, and Google may use free-tier requests to improve their models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .cardBackground()
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Reminders", systemImage: "bell.badge.fill")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { reminders.notificationsWanted },
                    set: { reminders.notificationsWanted = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify me when one is due")
                            .font(.subheadline.weight(.semibold))
                        Text(reminders.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(settings.theme.endColor)

                if reminders.authorizationDenied {
                    Button("Open iOS Settings") { reminders.openSystemSettings() }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Text("Reminders also stay listed on the Date tab whatever this is set to. Inside a container app like LiveContainer, iOS does not deliver a guest app's notifications — that's the container, not this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .cardBackground()
        }
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Note Writing Pattern", systemImage: "text.format")

            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $settings.notePattern)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Give an example of how you like notes written, e.g. \"10/10/2025 Abc Restaurant entry = 20$\" — new notes the AI creates will follow that style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .cardBackground()
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Theme", systemImage: "paintpalette")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        withAnimation(.snappy) { settings.theme = theme }
                    } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.gradient)
                                .frame(height: 48)
                                .overlay(alignment: .bottomLeading) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Capsule().fill(.white.opacity(0.85)).frame(width: 34, height: 5)
                                        Capsule().fill(.white.opacity(0.5)).frame(width: 52, height: 5)
                                    }
                                    .padding(8)
                                }
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
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Backup", systemImage: "externaldrive")

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    prepareExport()
                } label: {
                    actionRowLabel(notesStore.notes.isEmpty ? "Nothing to export" : "Export All Notes",
                                   systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(notesStore.notes.isEmpty)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        actionRowLabel("Share Backup File", systemImage: "arrow.up.doc")
                    }
                    Text(exportURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                Button {
                    showingImporter = true
                } label: {
                    actionRowLabel("Import Notes", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)

                Text("Export writes a JSON file the app keeps until the next export, so the share sheet can't lose it. Importing never deletes: it adds what you don't have and lets you choose whether notes that match should be replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .cardBackground()
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Start Over", systemImage: "trash")
            Button(role: .destructive) {
                showingClearAllConfirm = true
            } label: {
                actionRowLabel("Delete all \(notesStore.notes.count) note\(notesStore.notes.count == 1 ? "" : "s")",
                               systemImage: "trash.circle")
            }
            .buttonStyle(.plain)
            .disabled(notesStore.notes.isEmpty)
        }
    }

    private var importTitle: String {
        guard let preview = importPreview else { return "Import" }
        return "\(preview.newCount) new · \(preview.olderCount) older than yours · \(preview.newerCount) newer"
    }

    // MARK: - Pieces

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(settings.theme.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func actionRowLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(notesStore.notes.isEmpty && title.contains("Nothing") ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Key test

    private var isTestingKey: Bool {
        if case .testing = keyTest { return true }
        return false
    }

    private var keyTestLabel: String {
        switch keyTest {
        case .idle, .testing: return "Test key"
        case .ok: return "Working ✓"
        case .failed: return "Test again"
        }
    }

    private func testKey() {
        keyTest = .testing
        let key = settings.deepSeekAPIKey
        keyTestTask?.cancel()
        keyTestTask = Task { @MainActor in
            if let failure = await OnlineAI.verifyKey(key) {
                keyTest = .failed(failure.message)
                settings.lastAIError = failure.message
            } else {
                keyTest = .ok
                settings.lastAIError = nil
                coordinator.say("Your key works — the assistant can answer and make changes.")
            }
        }
    }

    // MARK: - Backup

    /// - Returns: true when the file is on disk, so anything that deletes afterwards can trust it.
    @discardableResult
    private func prepareExport() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notesStore.notes) else {
            statusMessage = "Couldn't prepare the export file."
            return false
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "SahandInfoNotes-\(formatter.string(from: Date())).json"

        // The old code wrote into the temporary directory, which iOS is free to empty at any
        // moment - including while the share sheet is still open, so "Share Backup File" could hand
        // over nothing. A file the app owns stays put until the next export.
        let directory = BackupStore.backupDirectory()
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            try? BackupStore.pruneOldBackups(keeping: url, in: directory)
            exportURL = url
            statusMessage = "Saved \(notesStore.notes.count) note(s) to \(filename)."
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            statusMessage = "Couldn't write the backup: \(error.localizedDescription)"
            return false
        }
    }

    /// Reads the file and shows what it would change *before* changing anything. Importing straight
    /// over newer work was a silent way to lose edits.
    private func inspectImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            statusMessage = "Import was cancelled."
        case .success(let url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode([Note].self, from: data)
                guard !decoded.isEmpty else {
                    statusMessage = "That file didn't contain any notes."
                    return
                }
                var newCount = 0, olderCount = 0, newerCount = 0
                for incoming in decoded {
                    guard let existing = notesStore.note(id: incoming.id) else {
                        newCount += 1
                        continue
                    }
                    if incoming.dateModified > existing.dateModified { newerCount += 1 } else { olderCount += 1 }
                }
                importPreview = ImportPreview(incoming: decoded,
                                             newCount: newCount,
                                             olderCount: olderCount,
                                             newerCount: newerCount)
            } catch {
                statusMessage = "That file couldn't be read as a notes backup."
            }
        }
    }

    /// `preferFile` false means "never lose a newer edit": a note that has been changed on this
    /// phone since the backup stays as it is. true takes the file's copy either way.
    private func applyImport(preferFile: Bool) {
        guard let preview = importPreview else { return }
        var merged = notesStore.notes
        var added = 0, replaced = 0, keptNewer = 0

        for incoming in preview.incoming {
            if let index = merged.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.dateModified > merged[index].dateModified {
                    merged[index] = incoming
                    replaced += 1
                } else if preferFile {
                    merged[index] = incoming
                    replaced += 1
                } else {
                    keptNewer += 1
                }
            } else {
                merged.append(incoming)
                added += 1
            }
        }
        // One write, so the whole import is a single entry on the Undo bar rather than N of them.
        notesStore.replaceAll(merged, label: "Imported \(added) new\(replaced > 0 ? " and updated \(replaced)" : "") note\(added + replaced == 1 ? "" : "s")")
        importPreview = nil
        statusMessage = "Added \(added), replaced \(replaced)" + (keptNewer > 0 ? ", kept \(keptNewer) newer note(s) untouched" : "") + "."
        coordinator.say(statusMessage ?? "Import finished.", actionLabel: "Undo", undoes: true)
    }
}

/// Where backups live and what to do with the pile. Kept out of the view so the local script and the
/// app agree on one location.
enum BackupStore {
    static func backupDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The ten most recent exports, so a week of daily backups can't fill the phone.
    ///
    /// Sorted by modification date on purpose: a directory hands back names in whatever order it
    /// likes, and dropping the tail of that order can throw away the newest backup - the one the
    /// user just made and was promised.
    static func pruneOldBackups(keeping current: URL, in directory: URL, limit: Int = 10) throws {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("SahandInfoNotes-") && $0 != current }
            .sorted { date($0) > date($1) }
        for url in backups.dropFirst(max(0, limit)) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func date(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}

// MARK: - Date (Reminders)

enum DateFilterMode: Equatable {
    case mostUrgent
    case leastUrgent
    case dateRange(Date, Date)
    case completedOnly
    case notCompletedOnly
    case overdue
}

struct DateView: View {
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var showingDateRangeSheet = false
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date().addingTimeInterval(7 * 24 * 60 * 60)
    /// Rows ticked in the last second stay on screen so the checkmark is actually seen. Removing the
    /// row inside the tap made "Done" look like the note had run away.
    @State private var recentlyTicked: Set<UUID> = []
    /// One timer per note: a single shared task meant that ticking two reminders in a row left the
    /// first one stuck in a "Not done" list forever, because the second tick cancelled its timer.
    @State private var tickClearTasks: [UUID: Task<Void, Never>] = [:]

    private var filter: DateFilterMode {
        get { coordinator.dateFilter }
        nonmutating set { coordinator.dateFilter = newValue }
    }

    private var isDateRangeSelected: Bool {
        if case .dateRange = filter { return true }
        return false
    }

    private var availableCategories: [String] {
        Array(Set(notesStore.notes.filter { $0.reminderDate != nil }.map { $0.categoryEnglish }.filter { !$0.isEmpty })).sorted()
    }

    /// Colour and wording come from the ranking the Notes tab uses too (see `ReminderTier`), computed
    /// over *every* reminder rather than the rows currently on screen. Two reasons: the outline means
    /// the same thing on both tabs, and switching a filter here cannot repaint anything - the colours
    /// used to follow whichever subset was visible, so a row turned red simply because you tapped
    /// "Not done".
    private var tiers: [UUID: ReminderTier] { notesStore.reminderTiers() }

    private func urgency(of note: Note) -> ReminderTier {
        tiers[note.id] ?? (note.isReminderCompleted ? .done : .later)
    }

    private var withReminders: [Note] {
        var list = notesStore.notes.filter { $0.reminderDate != nil }
        if let categoryFilter = coordinator.categoryFilter {
            list = list.filter { $0.categoryEnglish == categoryFilter }
        }
        return list
    }

    private var reminderNotes: [Note] {
        var list = withReminders
        switch filter {
        case .mostUrgent:
            list = list.filter { !$0.isReminderCompleted || recentlyTicked.contains($0.id) }
            return list.sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        case .leastUrgent:
            list = list.filter { !$0.isReminderCompleted || recentlyTicked.contains($0.id) }
            return list.sorted { ($0.reminderDate ?? .distantFuture) > ($1.reminderDate ?? .distantFuture) }
        case .dateRange(let start, let end):
            let bounds = start <= end ? (start, end) : (end, start)
            return list.filter { ($0.reminderDate ?? .distantPast) >= bounds.0 && ($0.reminderDate ?? .distantPast) <= bounds.1 }
                .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        case .completedOnly:
            return list.filter { $0.isReminderCompleted }.sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        case .notCompletedOnly:
            return list.filter { !$0.isReminderCompleted || recentlyTicked.contains($0.id) }
                .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        case .overdue:
            return list.filter { ($0.reminderDate ?? .distantFuture) < Date() && !$0.isReminderCompleted }
                .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        }
    }

    private var overdueCount: Int {
        withReminders.filter { ($0.reminderDate ?? .distantFuture) < Date() && !$0.isReminderCompleted }.count
    }

    private var visibleIDs: [UUID] { reminderNotes.map { $0.id } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SelectablePill(title: "Most urgent", systemImage: "flame.fill", isSelected: filter == .mostUrgent) {
                            setFilter(.mostUrgent)
                        }
                        if overdueCount > 0 {
                            SelectablePill(title: "Overdue \(overdueCount)", systemImage: "exclamationmark.triangle.fill",
                                           isSelected: filter == .overdue,
                                           tint: Color(red: 1.0, green: 0.23, blue: 0.19)) {
                                setFilter(.overdue)
                            }
                        }
                        SelectablePill(title: "Least urgent", isSelected: filter == .leastUrgent) {
                            setFilter(.leastUrgent)
                        }
                        SelectablePill(title: "Date range", systemImage: "calendar", isSelected: isDateRangeSelected) {
                            showingDateRangeSheet = true
                        }
                        SelectablePill(title: "Done", systemImage: "checkmark.circle", isSelected: filter == .completedOnly) {
                            setFilter(.completedOnly)
                        }
                        SelectablePill(title: "Not done", systemImage: "circle", isSelected: filter == .notCompletedOnly) {
                            setFilter(.notCompletedOnly)
                        }
                        if isDateRangeSelected {
                            Button("Clear range") { setFilter(.mostUrgent) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(settings.theme.endColor)
                                .padding(.horizontal, 10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                if !availableCategories.isEmpty {
                    CategoryChipsRow(categories: availableCategories,
                                      selection: $coordinator.categoryFilter,
                                      allLabel: "All Categories")
                }

                Group {
                    if reminderNotes.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(reminderNotes) { note in
                                reminderRow(note: note)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            notesStore.delete(ids: [note.id])
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .animation(.snappy, value: visibleIDs)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AmbientBackground())
            .navigationTitle("Date")
            .sheet(isPresented: $showingDateRangeSheet) {
                dateRangeSheet
            }
        }
    }

    private func setFilter(_ next: DateFilterMode) {
        withAnimation(.snappy) { coordinator.dateFilter = next }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label(filter == .overdue ? "Nothing overdue" : "No Reminders", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(filter == .overdue
                     ? "Every reminder is still in the future. That's good news."
                     : "Notes that have a date on them show up here, and iOS can tell you when one is due.")
            } actions: {
                if filter != .mostUrgent {
                    Button("Show all reminders") { setFilter(.mostUrgent) }
                        .buttonStyle(.bordered)
                }
                Button {
                    coordinator.selectedTab = .ask
                    coordinator.askDraft = "Remind me about my next note tomorrow at 9am"
                } label: {
                    Label("Ask the assistant to set one", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.theme.endColor)
            }
        }
    }

    private var dateRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $rangeStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("To", selection: $rangeEnd, displayedComponents: [.date, .hourAndMinute])
                if rangeStart > rangeEnd {
                    Label("I'll read this the other way round: \(rangeShort(rangeStart)) to \(rangeShort(rangeEnd)).",
                          systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Date Range")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        setFilter(.dateRange(rangeStart, rangeEnd))
                        showingDateRangeSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingDateRangeSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func rangeShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func reminderRow(note: Note) -> some View {
        let urgency = urgency(of: note)
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggleCompleted(note)
            } label: {
                Image(systemName: note.isReminderCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(urgency.color)
                    .contentShape(Circle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.isReminderCompleted ? "Mark not done" : "Mark done")

            Button {
                coordinator.reveal(noteID: note.id, in: notesStore)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundStyle(note.isReminderCompleted ? .secondary : .primary)
                        .strikethrough(note.isReminderCompleted)

                    Text(note.previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let date = note.reminderDate {
                        HStack(spacing: 6) {
                            Label(absoluteDateFormatter.string(from: date), systemImage: "calendar")
                            Text("·")
                            Text(urgency.label)
                                .fontWeight(.semibold)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(urgency.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Edit") {
                coordinator.reveal(noteID: note.id, in: notesStore, startEditing: true)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(settings.theme.endColor)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(urgency.color.opacity(note.isReminderCompleted ? 0 : 0.6), lineWidth: 1.5)
        )
        .flashWhenRecentlyChanged(note.id)
        .opacity(note.isReminderCompleted ? 0.75 : 1)
        .animation(.snappy(duration: 0.3), value: note.isReminderCompleted)
        // The outline eases into its new colour when a reminder moves tier (finished, or something
        // nearer came and went) instead of snapping. `urgency` is the local value: the row shadows
        // the method name, so calling it again here would resolve to the tier, not a function.
        .animation(.snappy(duration: 0.35), value: urgency)
    }

    private func toggleCompleted(_ note: Note) {
        let nowCompleted = !note.isReminderCompleted
        notesStore.setReminderCompleted(nowCompleted, for: note.id)
        guard nowCompleted else { return }
        // Let the checkmark be seen before the row can leave a filter.
        recentlyTicked.insert(note.id)
        tickClearTasks[note.id]?.cancel()
        let id = note.id
        tickClearTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                _ = recentlyTicked.remove(id)
                tickClearTasks[id] = nil
            }
        }
    }

}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var notesStore: NotesStore
    @EnvironmentObject var reminders: ReminderScheduler

    var body: some View {
        // The selection lives on the coordinator, not in here, which is what finally lets the
        // assistant (and the Date tab's empty state, and a fired reminder) move you somewhere.
        TabView(selection: $coordinator.selectedTab) {
            NotesListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(AppTab.notes)
            AskView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .tag(AppTab.ask)
            DateView()
                .tabItem { Label("Date", systemImage: "calendar") }
                .tag(AppTab.date)
        }
        .tint(settings.theme.endColor)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                AppNoticeBar()
                UndoBar()
            }
            // Clears the floating + button, which lives at the same corner.
            .padding(.bottom, 96)
            .padding(.top, 8)
            .animation(.snappy, value: coordinator.notice)
            .animation(.snappy, value: notesStore.undoOfferVisible)
            .animation(.snappy, value: notesStore.undoLabel)
        }
        .onChange(of: reminders.pendingNoteToOpen) { _, id in
            guard let id else { return }
            reminders.pendingNoteToOpen = nil
            coordinator.reveal(noteID: id, in: notesStore)
        }
    }
}

@main
struct SahandInfoApp: App {
    @StateObject private var notesStore = NotesStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var reminders = ReminderScheduler.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesStore)
                .environmentObject(settings)
                .environmentObject(coordinator)
                .environmentObject(reminders)
                .task {
                    // Permission is asked for on first launch rather than buried in a toggle nobody
                    // finds, and the schedule is rebuilt from the notes every time the app comes back
                    // so a reminder changed while offline still ends up correct.
                    reminders.configureOnce()
                    reminders.sync(with: notesStore.notes)
                    reminders.clearBadge()
                    // "The app looks empty" is not how a damaged save file should announce itself.
                    if let recovery = notesStore.recoveryNotice {
                        coordinator.say(recovery, actionLabel: "Open Settings", opensSettings: true)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    reminders.sync(with: notesStore.notes)
                    reminders.clearBadge()
                    // Covers a tap on a notification that arrived while the app was closed too: the
                    // schedule and the permission are both re-read rather than trusted from launch.
                    reminders.refreshAuthorizationStatus()
                }
        }
    }
}
