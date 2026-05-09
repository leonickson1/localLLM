//
//  Task.swift
//  LocalLLM
//

import Foundation
import SwiftUI

enum TaskCategory: String, CaseIterable, Identifiable {
    case llm = "Text Generation"
    case analysis = "Analysis"

    var id: String { rawValue }

    var displayName: String {
        return rawValue
    }
}

struct AITask: Identifiable, Hashable {
    let id: String
    let label: String
    let description: String
    let category: TaskCategory
    let icon: String
    let gradient: [Color]
    var models: [AIModel]
    let docUrl: String?
    let sourceCodeUrl: String?

    static func == (lhs: AITask, rhs: AITask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum BuiltInTaskID: String {
    case llmChat = "llm_chat"
    case llmFinance = "llm_finance"
    case llmHealth = "llm_health"
}

extension AITask {
    static let sampleTasks: [AITask] = [
        AITask(
            id: BuiltInTaskID.llmChat.rawValue,
            label: "Chat",
            description: "Chat, analyze images, transcribe audio, and generate text - all in one place.",
            category: .llm,
            icon: "sparkles",
            gradient: [],
            models: [],
            docUrl: nil,
            sourceCodeUrl: nil
        ),
        AITask(
            id: BuiltInTaskID.llmFinance.rawValue,
            label: "Finance",
            description: "Upload statements and get AI-powered expense analysis.",
            category: .analysis,
            icon: "creditcard.fill",
            gradient: [],
            models: [],
            docUrl: nil,
            sourceCodeUrl: nil
        ),
        AITask(
            id: BuiltInTaskID.llmHealth.rawValue,
            label: "Health",
            description: "Analyze steps and health metrics for personalized insights.",
            category: .analysis,
            icon: "heart.text.square.fill",
            gradient: [],
            models: [],
            docUrl: nil,
            sourceCodeUrl: nil
        ),
    ]
}
