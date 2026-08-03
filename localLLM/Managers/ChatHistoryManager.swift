//
//  ChatHistoryManager.swift
//  LocalLLM
//

import Foundation
import Combine
import SwiftUI

enum ChatTag: String, Codable, CaseIterable {
    case general = "General"
    case health = "Health"
    case finance = "Finance"
    case journal = "Journal"

    var color: Color {
        switch self {
        case .general: return .gray
        case .health: return .pink
        case .finance: return .blue
        case .journal: return .indigo
        }
    }

    var icon: String {
        switch self {
        case .general: return "message.fill"
        case .health: return "heart.fill"
        case .finance: return "creditcard.fill"
        case .journal: return "book.fill"
        }
    }
}

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var timestamp: Date
    var isPinned: Bool
    var tag: ChatTag

    // Backward compatibility: default to .general if tag is missing
    init(id: UUID, title: String, messages: [ChatMessage], timestamp: Date, isPinned: Bool, tag: ChatTag = .general) {
        self.id = id
        self.title = title
        self.messages = messages
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.tag = tag
    }
}

class ChatHistoryManager: ObservableObject {
    @Published var sessions: [ChatSession] = []

    private let saveKey = "chat_history_sessions"

    init() {
        loadSessions()
    }

    func saveSession(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persist()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        sessions.removeAll()
        persist()
    }

    func togglePin(id: UUID) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].isPinned.toggle()
            persist()
        }
    }

    func sessions(for tag: ChatTag? = nil) -> [ChatSession] {
        let filtered = tag == nil ? sessions : sessions.filter { $0.tag == tag }
        return filtered.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.timestamp > $1.timestamp
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.timestamp > $1.timestamp
            }
        }
    }
}
