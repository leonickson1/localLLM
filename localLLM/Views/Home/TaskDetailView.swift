//
//  TaskDetailView.swift
//  LocalLLM
//
//

import SwiftUI

struct TaskDetailView: View {
    let task: AITask
    @EnvironmentObject var modelManager: ModelManager
    @State private var selectedModel: AIModel?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                TaskHeaderView(task: task)
                
                // Description
                VStack(alignment: .leading, spacing: 16) {
                    Text("ABOUT")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
                    
                    Text(task.description)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineSpacing(6)
                }
                .padding(.horizontal)
                
                // Links
                if task.docUrl != nil || task.sourceCodeUrl != nil {
                    TaskLinksView(task: task)
                        .padding(.horizontal)
                }
                
                // Models Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("AVAILABLE MODELS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.tertiary)
                        
                        Spacer()
                        
                        Text("\(task.models.count)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal)
                    
                    if task.models.isEmpty {
                        EmptyModelsView()
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(task.models) { model in
                                NavigationLink(destination: destinationView(for: model)) {
                                    ModelListItemView(model: model)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func destinationView(for model: AIModel) -> some View {
        ChatView(model: model)
    }
}

struct TaskHeaderView: View {
    let task: AITask
    
    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 80, height: 80)
                
                Image(systemName: task.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)
            }
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(task.label)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct TaskLinksView: View {
    let task: AITask
    
    var body: some View {
        VStack(spacing: 12) {
            if let docUrl = task.docUrl, let url = URL(string: docUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "book")
                            .font(.system(size: 14))
                        Text("Documentation")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
            }
            
            if let sourceUrl = task.sourceCodeUrl, let url = URL(string: sourceUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 14))
                        Text("Source Code")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
            }
        }
    }
}

struct EmptyModelsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Models Available")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text("Download models from the Models tab to use this feature")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        TaskDetailView(task: AITask.sampleTasks[0])
            .environmentObject(ModelManager())
    }
}
