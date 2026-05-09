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

    var body: some Scene {
        WindowGroup {
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
                .preferredColorScheme(themeManager.currentScheme)
                .onReceive(NotificationCenter.default.publisher(for: .freeMemoryAction)) { _ in
                    Task { await inferenceManager.unloadModel() }
                }
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
