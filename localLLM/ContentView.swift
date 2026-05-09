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
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
    }
}

struct MainTabView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var selectedTab = 0

    private var defaultModel: AIModel {
        modelManager.downloadedModels.first ?? AIModel.sampleModels[0]
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
                FinanceView(model: defaultModel)
            }
            .tabItem {
                Label("Finance", systemImage: "creditcard.fill")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(3)
        }
        .tint(.blue)
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
}
