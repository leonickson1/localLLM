//
//  JournalManager.swift
//  LocalLLM
//
//  Persists journal entries and attached images to the app sandbox.
//  Files use iOS's default complete-protection encryption when the device is locked.
//

import Foundation
import UIKit
import Combine

@MainActor
class JournalManager: ObservableObject {

    @Published private(set) var entries: [JournalEntry] = []
    @Published var error: String?

    // Directory layout
    //   Documents/Journal/entries.json   <- all entries (one JSON array)
    //   Documents/Journal/Images/<uuid>.jpg <- attached images

    private static var journalDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Journal", isDirectory: true)
    }
    private static var entriesFile: URL { journalDir.appendingPathComponent("entries.json") }
    private static var imagesDir: URL { journalDir.appendingPathComponent("Images", isDirectory: true) }

    init() {
        ensureDirectories()
        loadEntries()
    }

    // MARK: - Directory setup

    private func ensureDirectories() {
        for dir in [Self.journalDir, Self.imagesDir] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Load / save

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: Self.entriesFile.path) else { return }
        do {
            let data = try Data(contentsOf: Self.entriesFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([JournalEntry].self, from: data)
            entries.sort { $0.date > $1.date }
        } catch {
            self.error = "Could not load journal entries: \(error.localizedDescription)"
            print("[JournalManager] Load failed: \(error)")
        }
    }

    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: Self.entriesFile, options: [.atomic])
        } catch {
            self.error = "Could not save journal: \(error.localizedDescription)"
            print("[JournalManager] Save failed: \(error)")
        }
    }

    // MARK: - CRUD

    func add(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
        saveEntries()
    }

    func update(_ entry: JournalEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        entries.sort { $0.date > $1.date }
        saveEntries()
    }

    func delete(_ entry: JournalEntry) {
        // Remove associated image files
        for filename in entry.imageFilenames {
            let url = Self.imagesDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    /// Wipe ALL journal data: entries file and every image. Used by the Settings reset option.
    func wipeAll() {
        try? FileManager.default.removeItem(at: Self.entriesFile)
        if FileManager.default.fileExists(atPath: Self.imagesDir.path) {
            if let files = try? FileManager.default.contentsOfDirectory(at: Self.imagesDir, includingPropertiesForKeys: nil) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
        }
        entries = []
        error = nil
    }

    // MARK: - Image storage

    /// Save a UIImage as a JPEG file in the journal images directory.
    /// Returns the filename (relative) so the entry can reference it.
    func saveImage(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = Self.imagesDir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            self.error = "Could not save image: \(error.localizedDescription)"
            return nil
        }
    }

    /// Load a UIImage from a stored filename. Returns nil if the file is missing.
    func loadImage(filename: String) -> UIImage? {
        let url = Self.imagesDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Calendar / filtering helpers

    /// Returns Set of Date (day-precision) for every day that has at least one entry. Used by the calendar dot view.
    var datesWithEntries: Set<Date> {
        var set = Set<Date>()
        let cal = Calendar.current
        for e in entries {
            set.insert(cal.startOfDay(for: e.date))
        }
        return set
    }

    func entries(on day: Date) -> [JournalEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        return entries.filter { cal.isDate($0.date, inSameDayAs: start) }
    }

    func entries(in range: ClosedRange<Date>) -> [JournalEntry] {
        entries.filter { range.contains($0.date) }
    }

    /// Search by content (title + body + tags).
    func search(query: String) -> [JournalEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(q) ||
            $0.body.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }
}
