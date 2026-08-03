//
//  localLLMApp.swift
//  LocalLLM
//
//  Created by Monish Soundar Raj on 12/16/25.
//

import SwiftUI

@main
struct localLLMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var modelManager = ModelManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var inferenceManager = InferenceManager()
    @StateObject private var parameterStore = ParameterStore()
    @StateObject private var healthManager = HealthManager()
    @StateObject private var financeManager = FinanceManager()
    @StateObject private var huggingFaceService = HuggingFaceService()
    @StateObject private var chatHistoryManager = ChatHistoryManager()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var openAICompat = OpenAICompatibleService()
    @StateObject private var journalManager = JournalManager()

    var body: some Scene {
        WindowGroup {
            if let comp = ProcessInfo.processInfo.environment["PREVIEW_COMPONENT"] {
                LLMGalleryHost(id: comp)
                    .environmentObject(parameterStore)
                    .environmentObject(healthManager)
                    .environmentObject(financeManager)
                    .preferredColorScheme(.light)
            } else if let scr = ProcessInfo.processInfo.environment["PREVIEW_SCREEN_ID"] {
                LLMScreenHost(id: scr)
                    .environmentObject(appState)
                    .environmentObject(modelManager)
                    .environmentObject(themeManager)
                    .environmentObject(inferenceManager)
                    .environmentObject(parameterStore)
                    .environmentObject(healthManager)
                    .environmentObject(financeManager)
                    .environmentObject(huggingFaceService)
                    .environmentObject(chatHistoryManager)
                    .environmentObject(ollamaService)
                    .environmentObject(openAICompat)
                    .environmentObject(journalManager)
                    .preferredColorScheme(.light)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(modelManager)
                    .environmentObject(themeManager)
                    .environmentObject(inferenceManager)
                    .environmentObject(parameterStore)
                    .environmentObject(healthManager)
                    .environmentObject(financeManager)
                    .environmentObject(huggingFaceService)
                    .environmentObject(chatHistoryManager)
                    .environmentObject(ollamaService)
                    .environmentObject(openAICompat)
                    .environmentObject(journalManager)
                    .preferredColorScheme(themeManager.currentScheme)
                    .onReceive(NotificationCenter.default.publisher(for: .freeMemoryAction)) { _ in
                        Task { await inferenceManager.unloadModel() }
                    }
            }
        }
    }
}

// MARK: - Component capture harness (gated behind PREVIEW_COMPONENT)

struct LLMGalleryHost: View {
    let id: String
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            content
                .frame(maxWidth: 360)
                .padding(20)
        }
    }

    @ViewBuilder private var content: some View {
        switch id {
        case "llm-arc-gauge":
            ArcGauge(label: "Move", value: 350, goal: 600, unit: "kcal",
                     gradient: [Color(red: 1, green: 0.22, blue: 0.37), .orange],
                     icon: "flame.fill", animate: false)
        case "llm-metric-bento":
            MetricBentoCard(icon: "figure.walk", iconColor: .orange, label: "Steps",
                            value: "8,234", unit: nil, change: 1200, isPositiveGood: true)
        case "llm-heart-rate-bento":
            HeartRateBentoCard(current: 72, resting: 65)
        case "llm-typing-indicator":
            TypingIndicator()
        case "llm-pdf-attachment":
            PDFAttachmentCard(name: "monthly_statement.pdf", charCount: 8512,
                              isTruncated: false, onTap: {}, onRemove: {})
        case "llm-hero-section":
            HeroSection()
        case "llm-account-pill":
            AccountPill(label: "Chase ···4521", isSelected: true, action: {})
        default:
            EmptyView()
        }
    }
}

// MARK: - App Delegate for Quick Actions

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: "free-memory",
                localizedTitle: "Free Memory",
                localizedSubtitle: "Unload model to free RAM",
                icon: UIApplicationShortcutIcon(systemImageName: "memorychip")
            )
        ]
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "free-memory" {
            NotificationCenter.default.post(name: .freeMemoryAction, object: nil)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}

extension Notification.Name {
    static let freeMemoryAction = Notification.Name("freeMemoryAction")
}

// MARK: - Screen capture harness (gated behind PREVIEW_SCREEN_ID)

struct LLMScreenHost: View {
    let id: String
    var body: some View {
        switch id {
        case "llm-home": HomeView()
        case "llm-health": HealthDashboardView()
        case "llm-settings": SettingsView()
        case "llm-models": ModelsView()
        case "llm-about": AboutView()
        default: Text("no screen \(id)")
        }
    }
}
