//
//  JournalCalendarView.swift
//  LocalLLM
//
//  Full month calendar — shown only as a sheet when the user taps the
//  calendar icon in the week strip. The main JournalView uses the compact
//  horizontal WeekStripView instead, so this never crowds the page.
//

import SwiftUI

struct JournalMonthSheet: View {
    @EnvironmentObject var journalManager: JournalManager
    @Binding var selectedDay: Date
    @State private var displayedMonth: Date = Date()
    @Environment(\.dismiss) var dismiss

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Month header with prev/next
                    HStack {
                        Button {
                            changeMonth(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Circle())
                        }

                        Spacer()

                        Text(monthLabel(for: displayedMonth))
                            .font(.system(size: 17, weight: .semibold))

                        Spacer()

                        Button {
                            changeMonth(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Circle())
                        }
                    }

                    // Weekday labels
                    HStack {
                        ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Day grid
                    let days = daysInMonth(for: displayedMonth)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(0..<days.count, id: \.self) { i in
                            if let date = days[i] {
                                JournalMonthDay(
                                    date: date,
                                    isSelected: calendar.isDate(date, inSameDayAs: selectedDay),
                                    isToday: calendar.isDateInToday(date),
                                    mood: dominantMood(for: date),
                                    hasEntry: journalManager.datesWithEntries.contains(calendar.startOfDay(for: date))
                                ) {
                                    selectedDay = calendar.startOfDay(for: date)
                                    dismiss()
                                }
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func changeMonth(by delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newMonth
            }
        }
    }

    private func daysInMonth(for date: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let daysCount = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let padding = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: padding)
        for d in 1...daysCount {
            if let day = calendar.date(byAdding: .day, value: d - 1, to: firstDay) {
                days.append(day)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func dominantMood(for day: Date) -> Mood? {
        let entries = journalManager.entries(on: day)
        guard !entries.isEmpty else { return nil }
        let counts = Dictionary(grouping: entries, by: { $0.mood }).mapValues { $0.count }
        return counts.max { $0.value < $1.value }?.key
    }
}

struct JournalMonthDay: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let mood: Mood?
    let hasEntry: Bool
    let onTap: () -> Void

    private var dayNumber: Int { Calendar.current.component(.day, from: date) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? .indigo : .primary))
                if let mood = mood {
                    Text(mood.emoji).font(.system(size: 11))
                } else if hasEntry {
                    Circle().fill(isSelected ? .white : .indigo).frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.indigo : (isToday ? Color.indigo.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
    }
}
