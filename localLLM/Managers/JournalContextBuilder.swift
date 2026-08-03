//
//  JournalContextBuilder.swift
//  LocalLLM
//
//  Builds prompt-ready journal context that fits the active backend's token budget.
//  Same chat code path runs against tiny on-device models AND huge cloud models, so the
//  truncation has to be careful — no silent drops, no overflows.
//

import Foundation

enum JournalContextBuilder {

    /// Conservative chars-per-token estimate for English. Slightly worse than real GPT tokenization
    /// but safer than over-packing the context.
    private static let charsPerToken: Int = 3

    struct Budget {
        /// Total input character budget for the entry text. Excludes the system prompt + response.
        let inputChars: Int
        /// Sentinel label used when older entries cannot fit — shown to the user so they know.
        let label: String
    }

    /// Pick a budget based on what backend is active.
    /// - `openAICompatActive`: cloud or local llama-server, generally large context
    /// - `ollamaActive`: Mac with Ollama, typically 8k+ for the kind of models people run there
    /// - `localContextTokens`: the on-device llama.cpp model's actual context size
    static func budget(
        openAICompatActive: Bool,
        ollamaActive: Bool,
        localContextTokens: Int
    ) -> Budget {
        if openAICompatActive {
            // OpenAI-compat could be anything from llama-server to GPT-4. Be generous but not infinite —
            // we still cap to keep cloud cost predictable and to avoid pathological prompts.
            return Budget(inputChars: 60_000, label: "cloud / llama-server")
        }
        if ollamaActive {
            // Most people running Ollama use 7B-13B with 8K-32K context. Reserve ~25% for prompt + response.
            return Budget(inputChars: 20_000, label: "Ollama")
        }
        // On-device path: derive from the loaded model's reported context size.
        // Reserve about half the context for the system prompt + response.
        let inputTokens = max(800, localContextTokens / 2)
        let inputChars = inputTokens * charsPerToken
        return Budget(inputChars: max(2_400, min(inputChars, 18_000)), label: "on-device")
    }

    struct Build {
        /// The text to put into the LLM userMessage. Already includes the entries and any compressed summary.
        let prompt: String
        let includedCount: Int
        let totalCount: Int
        /// True when older entries could not fit and were compressed into a one-line preamble.
        let wasTruncated: Bool
    }

    /// Build a packed journal context. Most recent entries are kept full; older entries are dropped
    /// in order. If anything was dropped, a one-line summary is prepended so the LLM knows context is incomplete.
    static func build(entries: [JournalEntry], budget: Budget) -> Build {
        guard !entries.isEmpty else {
            return Build(prompt: "(The user has no journal entries yet.)", includedCount: 0, totalCount: 0, wasTruncated: false)
        }

        // Entries are stored newest-first by JournalManager. Walk from newest to oldest, packing.
        let sorted = entries.sorted { $0.date > $1.date }
        var packed: [String] = []
        var charsUsed = 0
        var includedCount = 0
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        for entry in sorted {
            let segment = formatEntry(entry, formatter: formatter)
            if charsUsed + segment.count > budget.inputChars { break }
            packed.append(segment)
            charsUsed += segment.count
            includedCount += 1
        }

        let wasTruncated = includedCount < sorted.count
        var output = ""

        if wasTruncated {
            // Build a one-line preamble describing what we omitted, so the LLM can be honest with the user.
            let omitted = Array(sorted.dropFirst(includedCount))
            output += compressedSummary(of: omitted, formatter: formatter) + "\n\n"
        }

        output += "RECENT ENTRIES (most recent first):\n\n"
        output += packed.joined(separator: "\n---\n\n")

        return Build(
            prompt: output,
            includedCount: includedCount,
            totalCount: sorted.count,
            wasTruncated: wasTruncated
        )
    }

    // MARK: - Helpers

    /// Format a single entry. Body is truncated to a per-entry cap so one huge entry can't eat the whole budget.
    private static func formatEntry(_ entry: JournalEntry, formatter: DateFormatter) -> String {
        let perEntryBodyCap = 1_200
        let dateStr = formatter.string(from: entry.date)
        var body = entry.body
        if body.count > perEntryBodyCap {
            body = String(body.prefix(perEntryBodyCap)) + "... [truncated]"
        }
        var out = "[\(dateStr) - \(entry.mood.label)]"
        if !entry.title.isEmpty {
            out += "\nTitle: \(entry.title)"
        }
        out += "\n\(body)"
        if !entry.tags.isEmpty {
            out += "\nTags: \(entry.tags.joined(separator: ", "))"
        }
        return out
    }

    /// One-line preamble summarizing entries that did not fit in the budget.
    private static func compressedSummary(of entries: [JournalEntry], formatter: DateFormatter) -> String {
        guard !entries.isEmpty else { return "" }
        let earliest = entries.last?.date
        let latest = entries.first?.date

        // Mood distribution
        let moodCounts = Dictionary(grouping: entries, by: { $0.mood }).mapValues { $0.count }
        let topMoods = moodCounts.sorted { $0.value > $1.value }.prefix(2)
        let moodPart = topMoods.map { "\($0.key.label) (\($0.value))" }.joined(separator: ", ")

        // Top tags
        let allTags = entries.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 }).mapValues { $0.count }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        let tagPart = topTags.isEmpty ? "" : " Top tags: \(topTags.joined(separator: ", "))."

        var range = ""
        if let early = earliest, let late = latest {
            range = " from \(formatter.string(from: early)) to \(formatter.string(from: late))"
        }
        return "OLDER CONTEXT: \(entries.count) earlier entries\(range) were omitted to fit the model's context. Mood mix: \(moodPart).\(tagPart)"
    }
}

// MARK: - Helpers on JournalManager for stats the AI features need

extension JournalManager {
    /// Quick non-AI mood + activity stats for the Insights tab.
    func quickStats(within days: Int) -> QuickStats {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: Date()) else {
            return QuickStats(count: 0, moodCounts: [:], topTags: [], averageMoodScore: nil, mostActiveDayLabel: nil)
        }
        let recent = entries.filter { $0.date >= start }

        let moodCounts = Dictionary(grouping: recent, by: { $0.mood }).mapValues { $0.count }

        let allTags = recent.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 }).mapValues { $0.count }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        let scores = recent.map { $0.mood.score }
        let average: Double? = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)

        let byDay = Dictionary(grouping: recent) { cal.startOfDay(for: $0.date) }
        let busiest = byDay.max { $0.value.count < $1.value.count }
        let mostActiveDayLabel: String? = busiest.map { day -> String in
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return "\(f.string(from: day.key)) (\(day.value.count) entries)"
        }

        return QuickStats(
            count: recent.count,
            moodCounts: moodCounts,
            topTags: topTags,
            averageMoodScore: average,
            mostActiveDayLabel: mostActiveDayLabel
        )
    }
}

struct QuickStats {
    let count: Int
    let moodCounts: [Mood: Int]
    let topTags: [String]
    let averageMoodScore: Double?
    let mostActiveDayLabel: String?
}
