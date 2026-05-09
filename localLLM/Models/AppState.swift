//
//  AppState.swift
//  LocalLLM
//

import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var hasAcceptedTerms: Bool {
        didSet {
            UserDefaults.standard.set(hasAcceptedTerms, forKey: "hasAcceptedTerms")
        }
    }
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        self.hasAcceptedTerms = UserDefaults.standard.bool(forKey: "hasAcceptedTerms")
    }
    
    func acceptTerms() {
        hasAcceptedTerms = true
    }
    
    func showError(_ message: String) {
        errorMessage = message
    }
    
    func clearError() {
        errorMessage = nil
    }
}

