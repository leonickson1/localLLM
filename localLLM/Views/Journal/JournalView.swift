//
//  JournalView.swift
//  LocalLLM
//
//  Main journal tab. UI matches Health/Finance design language:
//  big bold heavy headline, BentoBackground cards, capsule buttons,
//  compact horizontal week strip instead of a half-page calendar.
//

import SwiftUI

struct JournalView: View {
    @EnvironmentObject var journalManager: JournalManager
    @State private var showNewEntry = false
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var editingEntry: JournalEntry?
    @State private var showAnalyze = false
    @State private var showMonthSheet = false
    @State private var searchText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header — matches Health / Finance
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JOURNAL")
                            .font(.system(size: 12, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(Date().formatted(date: .long, time: .omitted))
                            .font(.system(size: 28, weight: .heavy)).tracking(-0.5)
                    }
                    .padding(.horizontal)

                    // Compact week strip with mood emoji on entry days
                    WeekStripView(selectedDay: $selectedDay, onSeeMonth: { showMonthSheet = true })
                        .padding(.horizontal)

                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search entries", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .padding(.horizontal)

                    // Section header
                    HStack {
                        Text(sectionHeader)
                            .font(.system(size: 12, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !searchText.isEmpty {
                            Text("\(filteredEntries.count) results")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Entry list
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(filteredEntries) { entry in
                                Button { editingEntry = entry } label: {
                                    JournalEntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 110) // Room for the floating CTAs
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            // Floating actions row: bottom-centered "Analyze my journal" capsule + small + FAB on the right
            floatingActions
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showNewEntry) {
            JournalEntryEditor(entry: nil, initialDate: selectedDay)
        }
        .sheet(item: $editingEntry) { entry in
            JournalEntryEditor(entry: entry, initialDate: entry.date)
        }
        .sheet(isPresented: $showAnalyze) {
            JournalAnalyzeView()
        }
        .sheet(isPresented: $showMonthSheet) {
            JournalMonthSheet(selectedDay: $selectedDay)
        }
    }

    // MARK: - Floating action bar

    private var floatingActions: some View {
        HStack(spacing: 12) {
            // Analyze my journal (matches Health "Ask Health Coach" style)
            Button {
                showAnalyze = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Analyze my journal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Capsule().fill(Color(uiColor: .darkGray)))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            }
            .disabled(journalManager.entries.isEmpty)
            .opacity(journalManager.entries.isEmpty ? 0.5 : 1)

            // New entry FAB (matches the small purple+plus screenshot)
            Button {
                showNewEntry = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .shadow(color: .indigo.opacity(0.5), radius: 14, y: 6)
            }
            .accessibilityLabel("New entry")
        }
        .padding(.bottom, 22)
    }

    // MARK: - Computed

    private var filteredEntries: [JournalEntry] {
        if !searchText.isEmpty {
            return journalManager.search(query: searchText)
        }
        return journalManager.entries(on: selectedDay)
    }

    private var sectionHeader: String {
        if !searchText.isEmpty { return "SEARCH RESULTS" }
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "TODAY" }
        if cal.isDateInYesterday(selectedDay) { return "YESTERDAY" }
        return selectedDay.formatted(date: .complete, time: .omitted).uppercased()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No entries on this day yet" : "No matches")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Compact week strip

struct WeekStripView: View {
    @EnvironmentObject var journalManager: JournalManager
    @Binding var selectedDay: Date
    var onSeeMonth: () -> Void

    private let calendar = Calendar.current

    // 14 days back, 0 days forward (today is the rightmost)
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            WeekStripDay(
                                date: day,
                                isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                                isToday: calendar.isDateInToday(day),
                                mood: dominantMood(for: day),
                                hasEntry: journalManager.datesWithEntries.contains(day)
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedDay = day
                                }
                            }
                            .id(day)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    // Scroll to today (rightmost) on appear
                    if let today = days.last {
                        DispatchQueue.main.async {
                            proxy.scrollTo(today, anchor: .trailing)
                        }
                    }
                }
            }

            Button(action: onSeeMonth) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 56)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.leading, 6)
        }
    }

    private func dominantMood(for day: Date) -> Mood? {
        let entries = journalManager.entries(on: day)
        guard !entries.isEmpty else { return nil }
        // Pick the most common mood; tie-break by latest entry
        let counts = Dictionary(grouping: entries, by: { $0.mood })
            .mapValues { $0.count }
        return counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return false
        }?.key
    }
}

struct WeekStripDay: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let mood: Mood?
    let hasEntry: Bool
    let onTap: () -> Void

    private let calendar = Calendar.current

    private var dayNumber: Int { calendar.component(.day, from: date) }
    private var weekday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(weekday)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text("\(dayNumber)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? .white : (isToday ? .indigo : .primary))
                if let mood = mood {
                    Text(mood.emoji)
                        .font(.system(size: 14))
                } else if hasEntry {
                    Circle().fill(isSelected ? .white : .indigo).frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
            .frame(width: 44, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.indigo : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isToday && !isSelected ? Color.indigo : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Entry row

struct JournalEntryRow: View {
    @EnvironmentObject var journalManager: JournalManager
    let entry: JournalEntry

    var firstImage: UIImage? {
        guard let first = entry.imageFilenames.first else { return nil }
        return journalManager.loadImage(filename: first)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Mood emoji + time column
            VStack(spacing: 6) {
                Text(entry.mood.emoji)
                    .font(.system(size: 24))
                Text(entry.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if !entry.body.isEmpty {
                    // Render markdown inline so **bold** and *italic* show formatted in the preview.
                    Text(markdownAttributedString(from: entry.body))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                }
                if !entry.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let img = firstImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(BentoBackground())
    }
}

// MARK: - Markdown helper

/// Convert a journal body string into an AttributedString that renders supported markdown
/// (bold, italic, inline code, links). Lists / tables fall through as plain text — those
/// require a full markdown renderer which we're deferring to a future SPM dep.
func markdownAttributedString(from raw: String) -> AttributedString {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    if let attr = try? AttributedString(markdown: raw, options: options) {
        return attr
    }
    return AttributedString(raw)
}
