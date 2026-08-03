//
//  JournalAnalyzeView.swift
//  LocalLLM
//
//  Container sheet shown when the user taps "Analyze my journal" from JournalView.
//  Has two tabs: Insights (auto recap + AI summary + patterns) and Chat (Q&A over journal entries).
//

import SwiftUI

struct JournalAnalyzeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var tab: AnalyzeTab = .insights

    enum AnalyzeTab: String, CaseIterable, Identifiable {
        case insights, chat
        var id: String { rawValue }
        var label: String { self == .insights ? "Insights" : "Chat" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    ForEach(AnalyzeTab.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)

                Group {
                    switch tab {
                    case .insights:
                        JournalInsightsTab()
                    case .chat:
                        JournalChatView()
                    }
                }
            }
            .navigationTitle("Analyze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
