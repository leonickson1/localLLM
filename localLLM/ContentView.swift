//
//  ContentView.swift
//  LocalLLM
//
//  Created by Monish Soundar Raj on 12/16/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showTermsOfService = false

    var body: some View {
        Group {
            if appState.hasAcceptedTerms {
                MainTabView()
            } else {
                TermsOfServiceView(showTerms: $showTermsOfService)
                    .onAppear {
                        showTermsOfService = true
                    }
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @State private var selectedTab =
        Int(ProcessInfo.processInfo.environment["PREVIEW_TAB"] ?? "0") ?? 0

    private var defaultModel: AIModel {
        modelManager.defaultModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatView(model: defaultModel)
            }
            .tabItem {
                Label("Chat", systemImage: "sparkles")
            }
            .tag(0)

            NavigationStack {
                HealthView(model: defaultModel)
            }
            .tabItem {
                Label("Health", systemImage: "heart.fill")
            }
            .tag(1)

            NavigationStack {
                JournalView()
            }
            .tabItem {
                Label("Journal", systemImage: "book.fill")
            }
            .tag(2)

            NavigationStack {
                FinanceView(model: defaultModel)
            }
            .tabItem {
                Label("Finance", systemImage: "creditcard.fill")
            }
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(4)
        }
        .tint(.blue)
        .alert(
            "Load Large Model?",
            isPresented: Binding(
                get: { inferenceManager.pendingLoadConfirmation != nil },
                set: { _ in /* dismissal handled by buttons below */ }
            ),
            presenting: inferenceManager.pendingLoadConfirmation
        ) { confirmation in
            Button("Load Anyway") {
                let model = confirmation.model
                inferenceManager.pendingLoadConfirmation = nil
                Task { await inferenceManager.loadModel(model, forceLoad: true) }
            }
            Button("Cancel", role: .cancel) {
                inferenceManager.cancelPendingLoad()
            }
        } message: { confirmation in
            Text("\(confirmation.model.displayName) needs about \(confirmation.modelSizeMB) MB to run, and iOS only allows this app about \(confirmation.availableMB) MB on your device. Loading anyway may cause the app to crash. A smaller model is more reliable on this device.")
        }
        .alert(
            "Could Not Load Model",
            isPresented: Binding(
                get: { inferenceManager.loadError != nil },
                set: { if !$0 { inferenceManager.loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                inferenceManager.loadError = nil
            }
        } message: {
            Text(inferenceManager.loadError ?? "")
        }
        .alert(
            "Model May Not Fit",
            isPresented: Binding(
                get: { inferenceManager.blockedLoad != nil },
                set: { _ in /* dismissal handled by buttons below */ }
            ),
            presenting: inferenceManager.blockedLoad
        ) { blocked in
            Button("Try Anyway", role: .destructive) {
                let model = blocked.model
                inferenceManager.blockedLoad = nil
                // Crash-loop protection: clear the saved preference so a crash
                // does not auto-retry this model on next launch.
                modelManager.preferredModelId = nil
                Task { await inferenceManager.loadModel(model, forceLoad: true) }
            }
            Button("Cancel", role: .cancel) {
                inferenceManager.blockedLoad = nil
            }
        } message: { blocked in
            Text("\(blocked.model.displayName) needs about \(blocked.modelSizeMB) MB but iOS only gives this app about \(blocked.availableMB) MB on your device. Loading will likely crash the app. If you tap Try Anyway and the app crashes, on next launch we will fall back to a smaller model so you can pick a different one.")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ModelManager())
        .environmentObject(ThemeManager())
        .environmentObject(InferenceManager())
        .environmentObject(ParameterStore())
        .environmentObject(HealthManager())
        .environmentObject(FinanceManager())
        .environmentObject(HuggingFaceService())
        .environmentObject(OpenAICompatibleService())
        .environmentObject(JournalManager())
}
