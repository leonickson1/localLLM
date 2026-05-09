//
//  ThemeManager.swift
//  LocalLLM
//

import SwiftUI
import Combine

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

class ThemeManager: ObservableObject {
    @Published var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
            // Delay scheme change to next run loop to avoid UI hang
            DispatchQueue.main.async { [weak self] in
                self?.updateColorScheme()
            }
        }
    }

    @Published var currentScheme: ColorScheme?

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? AppTheme.system.rawValue
        self.selectedTheme = AppTheme(rawValue: savedTheme) ?? .system
        updateColorScheme()
    }

    private func updateColorScheme() {
        switch selectedTheme {
        case .system:
            currentScheme = nil
        case .light:
            currentScheme = .light
        case .dark:
            currentScheme = .dark
        }
    }
}

