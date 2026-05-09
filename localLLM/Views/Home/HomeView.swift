//
//  HomeView.swift
//  LocalLLM
//
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var selectedCategory: TaskCategory = .llm
    @State private var showImportSheet = false
    @State private var searchText = ""
    @Namespace private var animation
    
    private var filteredTasks: [AITask] {
        let categoryTasks = modelManager.tasks.filter { $0.category == selectedCategory }
        
        if searchText.isEmpty {
            return categoryTasks
        } else {
            return categoryTasks.filter { task in
                task.label.localizedCaseInsensitiveContains(searchText) ||
                task.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Modern Tech Background (Dark Mode Optimized)
                TechBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Hero Section
                        HeroSection()
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                        
                        // Category Selector
                        CategorySelector(
                            selectedCategory: $selectedCategory,
                            animation: animation
                        )
                        .padding(.horizontal, 24)
                        
                        // Task Grid
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ],
                            spacing: 16
                        ) {
                            ForEach(filteredTasks) { task in
                                NavigationLink(destination: destinationView(for: task)) {
                                    TaskCard(task: task)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                        
                        // Footer
                        FooterView()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search...")
            .sheet(isPresented: $showImportSheet) {
                ImportModelSheet()
            }
        }
    }
    
    // Navigate directly to Finance/Health views, others go through TaskDetailView
    @ViewBuilder
    private func destinationView(for task: AITask) -> some View {
        switch task.id {
        case BuiltInTaskID.llmChat.rawValue:
            // Unified chat - pick first downloaded model or first available
            let model = modelManager.downloadedModels.first ?? AIModel.sampleModels[0]
            ChatView(model: model)
        case BuiltInTaskID.llmFinance.rawValue:
            FinanceView(model: AIModel.sampleModels[0])
        case BuiltInTaskID.llmHealth.rawValue:
            HealthView(model: AIModel.sampleModels[0])
        default:
            TaskDetailView(task: task)
        }
    }
}

// MARK: - Components

struct HeroSection: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.5), radius: 4)
                Text("SYSTEM ONLINE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.05), lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Local")
                    .font(.system(size: 40, weight: .thin, design: .default))
                    .foregroundStyle(.primary)
                Text("Intelligence")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
            }
            
            Text("Private, on-device AI models running securely on your hardware.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 20)
        }
    }
}

struct CategorySelector: View {
    @Binding var selectedCategory: TaskCategory
    let animation: Namespace.ID
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskCategory.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        animation: animation
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}

struct CategoryButton: View {
    let category: TaskCategory
    let isSelected: Bool
    let animation: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category.displayName)
                .font(.system(size: 14, weight: .medium))
                // FIX: Ensure text contrasts with primary background (which is white in dark mode)
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary)
                            .matchedGeometryEffect(id: "bg", in: animation)
                    } else {
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TaskCard: View {
    let task: AITask
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon
            Image(systemName: task.icon)
                .font(.system(size: 24))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(task.label)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(task.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 8) // Prevent text from hitting the edge too hard
            }
            
            Spacer(minLength: 0)
            
            // Footer
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text("\(task.models.count) Models")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(minHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.5), lineWidth: 1)
                .blendMode(.overlay)
        )
    }
}

struct FooterView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("POWERED BY LLAMA.CPP")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}





#Preview {
    HomeView()
        .environmentObject(ModelManager())
}
