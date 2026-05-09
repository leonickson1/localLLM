//
//  ModelInfoSheet.swift
//  LocalLLM
//
//

import SwiftUI

struct ModelInfoSheet: View {
    let model: AIModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Model Information") {
                    InfoRow(label: "Name", value: model.displayName)
                    InfoRow(label: "Size", value: model.formattedSize)
                    InfoRow(label: "Status", value: model.isDownloaded ? "Downloaded" : "Not Downloaded")
                }
                
                Section("Description") {
                    Text(model.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Section("Parameters") {
                    InfoRow(label: "Temperature", value: String(format: "%.2f", model.parameters.temperature))
                    InfoRow(label: "Top K", value: "\(model.parameters.topK)")
                    InfoRow(label: "Top P", value: String(format: "%.2f", model.parameters.topP))
                    InfoRow(label: "Max Tokens", value: "\(model.parameters.maxTokens)")
                }
                
                if let huggingFaceUrl = model.huggingFaceUrl,
                   let url = URL(string: huggingFaceUrl) {
                    Section {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "link")
                                Text("View on Hugging Face")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model Info")
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

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    ModelInfoSheet(model: AIModel.sampleModels[0])
}

