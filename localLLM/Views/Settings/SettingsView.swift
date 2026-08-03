//
//  SettingsView.swift
//  LocalLLM
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var financeManager: FinanceManager
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var historyManager: ChatHistoryManager
    @EnvironmentObject var journalManager: JournalManager
    @State private var showAbout = false
    @State private var showLicenses = false
    @State private var showClearAlert = false
    @State private var showRecoveryAlert = false
    @State private var showWipeJournalAlert = false

    var body: some View {
            List {
                // Models Section
                Section {
                    NavigationLink {
                        ModelsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Models")
                                    .font(.system(size: 16, weight: .medium))
                                Spacer()
                                Text("\(modelManager.downloadedModels.count) downloaded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "cube.box.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    NavigationLink {
                        ExperimentalModelsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Experimental Models")
                                    .font(.system(size: 16, weight: .medium))
                                Text("ALPHA")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple.opacity(0.2)))
                                    .foregroundStyle(.purple)
                                Spacer()
                                Text("35B on-device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.badge.icloud")
                                .foregroundStyle(.purple)
                        }
                    }
                } header: {
                    Text("MODELS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Ollama Section
                Section {
                    Toggle(isOn: $ollamaService.isEnabled) {
                        Label {
                            Text("Ollama")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.blue)
                        }
                    }

                    if !ollamaService.isEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Run larger models on your Mac and route requests over local WiFi. Turn this on after starting your Ollama server.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("OLLAMA_HOST=0.0.0.0:11434 ollama serve")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .padding(.vertical, 2)
                        .listRowSeparator(.hidden)
                    }

                    if ollamaService.isEnabled {
                        HStack {
                            Label {
                                Text("Server")
                                    .font(.system(size: 16, weight: .medium))
                            } icon: {
                                Image(systemName: "network")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            TextField("192.168.1.x:11434", text: $ollamaService.serverURL)
                                .font(.system(size: 13, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            Task { await ollamaService.checkConnection() }
                        } label: {
                            HStack {
                                if ollamaService.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 20)
                                    Text("Testing...")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.secondary)
                                } else if ollamaService.isConnected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Connected")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.green)
                                } else if ollamaService.error != nil {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text("Failed - Tap to retry")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.red)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.blue)
                                    Text("Test Connection")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                            }
                        }
                        .disabled(ollamaService.isChecking)

                        if ollamaService.isConnected && !ollamaService.availableModels.isEmpty {
                            Picker(selection: $ollamaService.selectedModel) {
                                ForEach(ollamaService.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            } label: {
                                Label {
                                    Text("Default Model")
                                        .font(.system(size: 16, weight: .medium))
                                } icon: {
                                    Image(systemName: "cpu")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }

                        if ollamaService.isEnabled {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.open")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.orange)
                                Text("Data sent over local network without encryption. Use on trusted WiFi only.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange.opacity(0.06))
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                } header: {
                    Text("OLLAMA")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // OpenAI-Compatible Section
                Section {
                    Toggle(isOn: $openAICompat.isEnabled) {
                        Label {
                            Text("OpenAI-Compatible")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "cloud")
                                .foregroundStyle(.blue)
                        }
                    }

                    if !openAICompat.isEnabled {
                        Text("Connect to any server that speaks the OpenAI Chat Completions API: llama-server, vLLM, LM Studio, OpenAI, OpenRouter, Groq, and others. Turn this on to enter the URL and optional API key.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                            .listRowSeparator(.hidden)
                    }

                    if openAICompat.isEnabled {
                        HStack {
                            Label {
                                Text("Server URL")
                                    .font(.system(size: 16, weight: .medium))
                            } icon: {
                                Image(systemName: "network")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            TextField("http://192.168.1.x:8080", text: $openAICompat.baseURL)
                                .font(.system(size: 13, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }

                        HStack {
                            Label {
                                Text("API Key")
                                    .font(.system(size: 16, weight: .medium))
                            } icon: {
                                Image(systemName: "key")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            SecureField("Optional", text: $openAICompat.apiKey)
                                .font(.system(size: 13, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            Task { await openAICompat.checkConnection() }
                        } label: {
                            HStack {
                                if openAICompat.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 20)
                                    Text("Testing...")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.secondary)
                                } else if openAICompat.isConnected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Connected")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.green)
                                } else if openAICompat.error != nil {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text("Failed - Tap to retry")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.red)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.blue)
                                    Text("Test Connection")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                            }
                        }
                        .disabled(openAICompat.isChecking)

                        if openAICompat.isConnected && !openAICompat.availableModels.isEmpty {
                            Picker(selection: $openAICompat.selectedModel) {
                                ForEach(openAICompat.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            } label: {
                                Label {
                                    Text("Default Model")
                                        .font(.system(size: 16, weight: .medium))
                                } icon: {
                                    Image(systemName: "cpu")
                                        .foregroundStyle(.primary)
                                }
                            }
                        } else if openAICompat.isConnected {
                            HStack {
                                Label {
                                    Text("Model ID")
                                        .font(.system(size: 16, weight: .medium))
                                } icon: {
                                    Image(systemName: "cpu")
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                TextField("e.g. llama-3.1-8b-instruct", text: $openAICompat.selectedModel)
                                    .font(.system(size: 13, design: .monospaced))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }

                        if let err = openAICompat.error, !openAICompat.isChecking {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }

                        Toggle(isOn: $openAICompat.allowSelfSignedCerts) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Trust self-signed certificates")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Advanced. Only enable for trusted local LAN servers.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "lock.shield")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("OPENAI-COMPATIBLE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Appearance Section
                Section {
                    Picker("Theme", selection: $themeManager.selectedTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("APPEARANCE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Model Settings
                Section {
                    NavigationLink {
                        ModelParametersView()
                    } label: {
                        Label {
                            Text("Parameters")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.primary)
                        }
                    }

                    NavigationLink {
                        BenchmarkSettingsView()
                    } label: {
                        Label {
                            Text("Benchmarks")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "speedometer")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("CONFIGURATION")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Storage Section
                Section {
                    HStack {
                        Label {
                            Text("Models Cache")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "internaldrive")
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(modelManager.formattedCacheSize())
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let availableSpace = modelManager.availableDiskSpace() {
                        HStack {
                            Label {
                                Text("Available Space")
                                    .font(.system(size: 16, weight: .medium))
                            } icon: {
                                Image(systemName: "externaldrive")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Text("Clear All Downloaded Models")
                    }

                    Button(role: .destructive) {
                        showWipeJournalAlert = true
                    } label: {
                        HStack {
                            Text("Delete All Journal Entries")
                            Spacer()
                            Text("\(journalManager.entries.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(journalManager.entries.isEmpty)
                } header: {
                    Text("STORAGE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Recovery
                Section {
                    Button {
                        Task {
                            await inferenceManager.unloadModel()
                        }
                    } label: {
                        Label {
                            Text("Unload Current Model")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "memorychip")
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(!inferenceManager.isModelLoaded)

                    Button(role: .destructive) {
                        showRecoveryAlert = true
                    } label: {
                        Label {
                            Text("Reset App Data")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("TROUBLESHOOTING")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                } footer: {
                    Text("Unload frees memory if the app is slow. Reset clears chat history, finance data, and settings but keeps downloaded models.")
                        .font(.caption2)
                }

                // About Section
                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label {
                            Text("About LocalLLM")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.primary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "https://huggingface.co/models?search=gguf")!) {
                        Label {
                            Text("Model Library")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "cube.box")
                                .foregroundStyle(.primary)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/ggerganov/llama.cpp")!) {
                        Label {
                            Text("Documentation")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "book")
                                .foregroundStyle(.primary)
                        }
                    }

                    Button {
                        showLicenses = true
                    } label: {
                        Label {
                            Text("Licenses")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.primary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "https://github.com/leonickson1/localLLM/blob/main/PRIVACY.md")!) {
                        Label {
                            Text("Privacy Policy & Terms")
                                .font(.system(size: 16, weight: .medium))
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("INFORMATION")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }

                // Privacy Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("100% On-Device")
                                .font(.system(size: 14, weight: .semibold))
                            Text("No data leaves your device")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // App Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 Beta")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showLicenses) {
                LicensesView()
            }
            .alert("Clear Cache", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    modelManager.clearCache()
                }
            } message: {
                Text("This will delete all downloaded models. You'll need to re-download them to use them.")
            }
            .alert("Delete All Journal Entries?", isPresented: $showWipeJournalAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    journalManager.wipeAll()
                }
            } message: {
                Text("This will permanently delete every journal entry and attached image on this device. This cannot be undone.")
            }
            .alert("Reset All App Data?", isPresented: $showRecoveryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Everything", role: .destructive) {
                    Task {
                        await inferenceManager.unloadModel()
                        financeManager.clearAllTransactions()
                        healthManager.disconnect()
                        historyManager.clearAll()
                        journalManager.wipeAll()
                        parameterStore.resetToDefaults()
                    }
                }
            } message: {
                Text("This will clear all chat history, finance data, health connection, and settings. Downloaded models will not be deleted.")
            }
    }
}

struct ModelParametersView: View {
    @EnvironmentObject var parameterStore: ParameterStore

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Temperature")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2f", parameterStore.temperature))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $parameterStore.temperature, in: 0...2, step: 0.1)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Top K")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(parameterStore.topK)")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(parameterStore.topK) },
                        set: { parameterStore.topK = Int($0) }
                    ), in: 1...100, step: 1)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Top P")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2f", parameterStore.topP))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $parameterStore.topP, in: 0...1, step: 0.05)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max Tokens")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(parameterStore.maxTokens)")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(parameterStore.maxTokens) },
                        set: { parameterStore.maxTokens = Int($0) }
                    ), in: 128...4096, step: 128)
                }
                .padding(.vertical, 4)
            } header: {
                Text("GENERATION")
            }

            Section {
                Button("Reset to Defaults") {
                    parameterStore.resetToDefaults()
                }
            }
        }
        .navigationTitle("Parameters")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BenchmarkSettingsView: View {
    @EnvironmentObject var parameterStore: ParameterStore

    var body: some View {
        Form {
            Section {
                Toggle("Show Benchmarks", isOn: $parameterStore.showBenchmarks)
            } footer: {
                Text("Display real-time performance metrics during inference")
            }

            if parameterStore.showBenchmarks {
                Section("Metrics") {
                    Toggle("Time to First Token (TTFT)", isOn: $parameterStore.showTTFT)
                    Toggle("Tokens per Second", isOn: $parameterStore.showTokensPerSecond)
                }
            }
        }
        .navigationTitle("Benchmarks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 100, height: 100)
                                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))

                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.primary)
                        }

                        VStack(spacing: 4) {
                            Text("LocalLLM")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("Version 1.0.0 Beta")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.headline)

                        Text("Your personal AI assistant running 100% on your device. Chat with AI, analyze health data, track finances - all with complete privacy. No internet required after setup.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Powered By")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            TechnologyRow(name: "llama.cpp", icon: "bolt.fill")
                            TechnologyRow(name: "SwiftUI", icon: "swift")
                            TechnologyRow(name: "On-Device ML", icon: "cpu")
                            TechnologyRow(name: "HealthKit", icon: "heart.fill")
                            TechnologyRow(name: "Vision OCR & PDFKit", icon: "doc.text.viewfinder")
                            TechnologyRow(name: "Privacy First", icon: "lock.shield.fill")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("Made with care for Privacy\nYour data never leaves your device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TechnologyRow: View {
    let name: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(name)
                .font(.system(size: 16, weight: .medium))
        }
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LicenseSection(
                        name: "LocalLLM",
                        license: "Open Source",
                        text: "Your personal AI assistant"
                    )

                    LicenseSection(
                        name: "llama.cpp",
                        license: "MIT License",
                        text: "LLM inference engine by Georgi Gerganov"
                    )

                    LicenseSection(
                        name: "GGUF Models",
                        license: "Various Licenses",
                        text: "Individual model licenses apply. Check Hugging Face for details."
                    )
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LicenseSection: View {
    let name: String
    let license: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)

            Text(license)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
        .environmentObject(AppState())
        .environmentObject(ModelManager())
        .environmentObject(ParameterStore())
}
