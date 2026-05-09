//
//  ImportModelSheet.swift
//  LocalLLM
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportModelSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var modelManager: ModelManager
    @State private var showFilePicker = false
    @State private var displayName = ""
    @State private var selectedFileURL: URL?
    @State private var fileSize: String = ""
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: selectedFileURL != nil ? "doc.fill" : "doc.badge.plus")
                                .foregroundColor(.blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedFileURL != nil ? "File Selected" : "Select GGUF File")
                                    .foregroundColor(.primary)

                                if let url = selectedFileURL {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if !fileSize.isEmpty {
                                        Text(fileSize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Model File")
                } footer: {
                    Text("Select a .gguf model file from your device or Files app")
                }

                if selectedFileURL != nil {
                    Section {
                        TextField("Model Name", text: $displayName)
                    } header: {
                        Text("Display Name")
                    } footer: {
                        Text("This name will appear in the model picker")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text("GGUF format models are supported")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        Label {
                            Text("The file will be copied to the app's storage")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(.blue)
                        }

                        Label {
                            Text("Find models at huggingface.co")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundColor(.orange)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Import Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("Import") {
                            importModel()
                        }
                        .disabled(selectedFileURL == nil || displayName.isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "gguf") ?? .data,
                    UTType(filenameExtension: "bin") ?? .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selectedFileURL = url

                        // Auto-fill display name from filename
                        let name = url.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: "-", with: " ")
                            .replacingOccurrences(of: "_", with: " ")
                        displayName = name

                        // Show file size
                        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
                           let size = resources.fileSize {
                            fileSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                        }
                    }
                case .failure(let error):
                    print("[ImportModel] Error: \(error)")
                }
            }
        }
    }

    private func importModel() {
        guard let url = selectedFileURL else { return }
        isImporting = true
        let name = displayName.lowercased().replacingOccurrences(of: " ", with: "-")
        modelManager.importModel(from: url, name: name, displayName: displayName)
        isImporting = false
        dismiss()
    }
}
