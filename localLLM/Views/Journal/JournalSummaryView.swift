//
//  JournalSummaryView.swift
//  LocalLLM
//
//  Insights tab — the AI-powered reflection over recent entries.
//  Mounted inside JournalAnalyzeView; also kept as a standalone view for back-compat.
//

import SwiftUI

// Legacy entry point so any existing code that says `JournalSummaryView()` still works.
struct JournalSummaryView: View {
    var body: some View {
        NavigationStack {
            JournalInsightsTab()
                .navigationTitle("Insights")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Insights tab content

struct JournalInsightsTab: View {
    @EnvironmentObject var journalManager: JournalManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @EnvironmentObject var parameterStore: ParameterStore

    @State private var range: SummaryRange = .week
    @State private var isGenerating = false
    @State private var summaryText: String = ""
    @State private var patternsText: String = ""
    @State private var hasGenerated = false
    @State private var contextInfo: JournalContextBuilder.Build?

    enum SummaryRange: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var label: String { self == .week ? "Past week" : "Past month" }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Range selector
                Picker("Range", selection: $range) {
                    ForEach(SummaryRange.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: range) { _, _ in resetForNewRange() }

                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    quickStatsCard
                    moodDistributionCard

                    if !backendAvailable {
                        noBackendCard
                    } else {
                        generateButton
                        if !summaryText.isEmpty { reflectionCard }
                        if !patternsText.isEmpty { patternsCard }
                    }
                }
                Spacer().frame(height: 24)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No entries in this range yet.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var quickStatsCard: some View {
        let stats = journalManager.quickStats(within: range.days)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECAP")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                statRow(icon: "doc.text", label: "Entries", value: "\(stats.count)")
                if let avg = stats.averageMoodScore {
                    statRow(icon: "chart.line.uptrend.xyaxis", label: "Average mood", value: String(format: "%.1f / 5", avg))
                }
                if let busy = stats.mostActiveDayLabel {
                    statRow(icon: "calendar", label: "Most active day", value: busy)
                }
                if !stats.topTags.isEmpty {
                    statRow(icon: "tag", label: "Top tags", value: stats.topTags.joined(separator: ", "))
                }
            }
        }
        .padding(20)
        .background(BentoBackground())
        .padding(.horizontal)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var moodDistributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MOOD")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 14) {
                ForEach(Mood.allCases) { m in
                    let count = filteredEntries.filter { $0.mood == m }.count
                    VStack(spacing: 4) {
                        Text(m.emoji).font(.system(size: 22))
                            .opacity(count > 0 ? 1.0 : 0.25)
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(count > 0 ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(BentoBackground())
        .padding(.horizontal)
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Reading your entries...")
                } else {
                    Image(systemName: hasGenerated ? "arrow.clockwise" : "sparkles")
                    Text(hasGenerated ? "Regenerate" : "Generate insight")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.indigo)
            .clipShape(Capsule())
        }
        .disabled(isGenerating)
        .padding(.horizontal)
    }

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.indigo)
                Text("REFLECTION")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let info = contextInfo, info.wasTruncated {
                    Text("Based on \(info.includedCount) of \(info.totalCount) entries")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(summaryText)
                .font(.system(size: 15))
                .foregroundStyle(.primary.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BentoBackground())
        .padding(.horizontal)
    }

    private var patternsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.indigo)
                Text("PATTERNS I NOTICE")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(patternsText)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BentoBackground())
        .padding(.horizontal)
    }

    private var noBackendCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text("Load a local model in the Chat tab, or turn on Ollama / OpenAI-compatible in Settings, to generate AI insights.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(BentoBackground())
        .padding(.horizontal)
    }

    // MARK: - Computed

    private var filteredEntries: [JournalEntry] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -range.days, to: Date()) else { return [] }
        return journalManager.entries.filter { $0.date >= start }
    }

    private var backendAvailable: Bool {
        (openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty) ||
        (ollamaService.isEnabled && ollamaService.isConnected) ||
        inferenceManager.isModelLoaded
    }

    private func resetForNewRange() {
        hasGenerated = false
        summaryText = ""
        patternsText = ""
        contextInfo = nil
    }

    // MARK: - Generation

    private func generate() async {
        isGenerating = true
        summaryText = ""
        patternsText = ""
        defer { isGenerating = false }

        let budget = JournalContextBuilder.budget(
            openAICompatActive: openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty,
            ollamaActive: ollamaService.isEnabled && ollamaService.isConnected,
            localContextTokens: inferenceManager.activeContextWindow
        )
        let info = JournalContextBuilder.build(entries: filteredEntries, budget: budget)
        contextInfo = info

        // First pass: warm narrative reflection
        let reflectionSystem = "You are a thoughtful, warm reflection partner. Read someone's recent journal entries and surface what feels important. Refer to specific dates when relevant. Do not fabricate. Speak to them using \"you\". 3-5 short paragraphs."
        let reflectionUser = info.prompt + "\n\nWrite the reflection now."

        await streamBackend(systemPrompt: reflectionSystem, userMessage: reflectionUser) { token in
            summaryText += token
        }

        // Second pass: concrete patterns (only if first pass produced something)
        guard !summaryText.isEmpty else { hasGenerated = false; return }

        let patternsSystem = "You read the user's journal entries and call out 3-5 specific concrete patterns or recurring themes you notice. Each as one short bullet starting with \"-\". Be specific (mention dates, tags, repeated words). No generic advice. No preamble."
        let patternsUser = info.prompt + "\n\nList the patterns now."

        await streamBackend(systemPrompt: patternsSystem, userMessage: patternsUser) { token in
            patternsText += token
        }
        hasGenerated = true
    }

    /// Stream the active backend's response, invoking onToken for each chunk.
    private func streamBackend(systemPrompt: String, userMessage: String, onToken: @escaping (String) -> Void) async {
        let useOpenAI = openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty
        let useOllama = !useOpenAI && ollamaService.isEnabled && ollamaService.isConnected
        let useLocal  = !useOpenAI && !useOllama && inferenceManager.isModelLoaded

        if useOpenAI {
            let stream = openAICompat.streamChat(systemPrompt: systemPrompt, userMessage: userMessage)
            for await token in stream { onToken(token) }
        } else if useOllama {
            let stream = ollamaService.streamChat(systemPrompt: systemPrompt, userMessage: userMessage)
            for await token in stream { onToken(token) }
        } else if useLocal {
            let formatted = PromptFormatter.format(
                systemPrompt: systemPrompt,
                messages: [MessageTurn(role: "user", content: userMessage)],
                template: .chatml,
                contextTokens: inferenceManager.activeContextWindow
            )
            let stream = inferenceManager.generate(prompt: formatted, parameters: parameterStore.asModelParameters)
            for await token in stream { onToken(token) }
        }
    }
}
