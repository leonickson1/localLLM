//
//  JournalEntry.swift
//  LocalLLM
//
//  Single journal entry. All data stays on device.
//

import Foundation

struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var mood: Mood
    var date: Date
    var tags: [String]
    /// File names of images stored in the journal images directory. Relative names only,
    /// so the absolute path can change if Apple migrates the sandbox between updates.
    var imageFilenames: [String]
    /// Link previews parsed from URLs in the body. Cached so we do not re-fetch on every open.
    var linkPreviews: [LinkPreview]

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        mood: Mood = .mixed,
        date: Date = Date(),
        tags: [String] = [],
        imageFilenames: [String] = [],
        linkPreviews: [LinkPreview] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.mood = mood
        self.date = date
        self.tags = tags
        self.imageFilenames = imageFilenames
        self.linkPreviews = linkPreviews
    }
}

// MARK: - Mood

/// Unique weather-based mood scale. More distinctive than the standard 5-emoji face
/// scale, and the metaphor (weather) gives a softer way to log feelings.
enum Mood: String, Codable, CaseIterable, Identifiable {
    case stormy
    case cloudy
    case mixed
    case bright
    case radiant

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .stormy:  return "🌧️"
        case .cloudy:  return "☁️"
        case .mixed:   return "⛅"
        case .bright:  return "🌤️"
        case .radiant: return "☀️"
        }
    }

    var label: String {
        switch self {
        case .stormy:  return "Stormy"
        case .cloudy:  return "Cloudy"
        case .mixed:   return "Mixed"
        case .bright:  return "Bright"
        case .radiant: return "Radiant"
        }
    }

    /// Numerical value 1-5 for sorting / averaging / charts.
    var score: Int {
        switch self {
        case .stormy:  return 1
        case .cloudy:  return 2
        case .mixed:   return 3
        case .bright:  return 4
        case .radiant: return 5
        }
    }
}

// MARK: - Link Preview

struct LinkPreview: Codable, Equatable, Identifiable {
    var id: UUID
    var urlString: String
    var title: String?
    var description: String?
    var imageURL: String?
    var siteName: String?

    init(id: UUID = UUID(), urlString: String, title: String? = nil, description: String? = nil, imageURL: String? = nil, siteName: String? = nil) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }
}
