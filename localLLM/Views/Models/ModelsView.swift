//
//  ModelsView.swift
//  LocalLLM
//

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var huggingFaceService: HuggingFaceService
    @State private var selectedSegment = 0
    @State private var searchText = ""
    @State private var showImportSheet = false

    var filteredModels: [AIModel] {
        let models: [AIModel]
        switch selectedSegment {
        case 0: models = modelManager.availableModels
        case 1: models = huggingFaceService.remoteModels
        case 2: models = modelManager.downloadedModels
        default: models = []
        }

        if searchText.isEmpty {
            return models
        } else {
            return models.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
            ZStack {
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if selectedSegment == 1 && huggingFaceService.isLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Fetching models from HuggingFace...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 40)
                            } else if selectedSegment == 1 && huggingFaceService.remoteModels.isEmpty && !huggingFaceService.isLoading {
                                VStack(spacing: 16) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                    Text("Tap to browse community models")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        Task { await huggingFaceService.fetchModels() }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Load Models")
                                        }
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                    }
                                }
                                .padding(.vertical, 40)
                            } else {
                                ForEach(filteredModels) { model in
                                    ModelCardView(model: model)
                                }
                                .padding(.horizontal)
                            }
                        } header: {
                            VStack(spacing: 0) {
                                Picker("Models", selection: $selectedSegment) {
                                    Text("Built-in").tag(0)
                                    Text("Community").tag(1)
                                    Text("Downloaded").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.top, 0)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showImportSheet = true
                        } label: {
                            Label("Import GGUF File", systemImage: "doc.badge.plus")
                        }
                        if selectedSegment == 1 {
                            Button {
                                Task { await huggingFaceService.fetchModels() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search models")
            .sheet(isPresented: $showImportSheet) {
                ImportModelSheet()
            }
            .overlay {
                if filteredModels.isEmpty && selectedSegment != 1 {
                    EmptyModelsListView(isDownloaded: selectedSegment == 2)
                }
            }
            .alert("Download Error", isPresented: Binding(
                get: { modelManager.downloadError != nil },
                set: { if !$0 { modelManager.downloadError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modelManager.downloadError ?? "")
            }
            .navigationTitle("Models")
    }
}

struct ModelCardView: View {
    let model: AIModel
    @EnvironmentObject var modelManager: ModelManager
    @State private var showDeleteAlert = false

    // Read live state from modelManager so progress updates show
    private var liveModel: AIModel {
        modelManager.availableModels.first(where: { $0.id == model.id }) ?? model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(model.formattedSize)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        if liveModel.isDownloaded {
                            Text("INSTALLED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }

                Spacer()

                if liveModel.isDownloading {
                    VStack(spacing: 4) {
                        ProgressView(value: liveModel.downloadProgress)
                            .progressViewStyle(.circular)
                            .frame(width: 24, height: 24)
                        Text("\(Int(liveModel.downloadProgress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Description
            Text(model.description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.5)

            // Actions
            // Download progress bar
            if liveModel.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: liveModel.downloadProgress)
                        .tint(.blue)
                    HStack {
                        Text("Downloading... \(Int(liveModel.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            modelManager.cancelDownload(model)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    }
                }
            }

            HStack(spacing: 12) {
                if liveModel.isDownloading {
                    EmptyView() // Progress bar shown above
                } else if !liveModel.isDownloaded {
                    DownloadButton(model: model)
                } else {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.05))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let huggingFaceUrl = model.huggingFaceUrl,
                   let url = URL(string: huggingFaceUrl) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.system(size: 16))
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: .secondarySystemFill))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .alert("Delete Model", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelManager.deleteModel(model)
            }
        } message: {
            Text("Are you sure you want to delete \(model.displayName)? This action cannot be undone.")
        }
    }
}

struct EmptyModelsListView: View {
    let isDownloaded: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isDownloaded ? "cube.box" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text(isDownloaded ? "No Downloaded Models" : "No Models Found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

                Text(isDownloaded ?
                     "Models you download will appear here" :
                     "Try adjusting your search")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - Download Button (resolves community URLs before downloading)

struct DownloadButton: View {
    let model: AIModel
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var huggingFaceService: HuggingFaceService
    @State private var isResolving = false

    var body: some View {
        Button {
            print("[ModelsView] Download tapped for: \(model.displayName)")
            startDownload()
        } label: {
            HStack {
                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text(isResolving ? "Preparing..." : "Download")
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isResolving)
    }

    private func startDownload() {
        if model.modelUrl.isEmpty {
            // Community model - need to resolve URL first
            isResolving = true
            Task {
                if let resolved = await huggingFaceService.resolveDownloadURL(for: model) {
                    if !modelManager.availableModels.contains(where: { $0.id == resolved.id }) {
                        modelManager.availableModels.append(resolved)
                    }
                    modelManager.downloadModel(resolved)
                } else {
                    modelManager.downloadError = "Could not find a suitable GGUF file for this model."
                }
                isResolving = false
            }
        } else {
            // Built-in model - URL already known
            if !modelManager.availableModels.contains(where: { $0.id == model.id }) {
                modelManager.availableModels.append(model)
            }
            modelManager.downloadModel(model)
        }
    }
}

#Preview {
    ModelsView()
        .environmentObject(ModelManager())
        .environmentObject(HuggingFaceService())
}
