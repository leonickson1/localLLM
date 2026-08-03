//
//  StreamedModelsView.swift
//  LocalLLM
//
//  Showcase + honest expectations for Swiftlet streamed MoE models: models
//  far larger than device RAM that stream experts from storage on demand.
//  Layout mirrors ModelsView (gradient + card list); the model row is the
//  same ModelCardView used by Built-in/Community, so Download/progress/
//  Remove/Hugging Face behave identically everywhere.
//

import SwiftUI

struct ExperimentalModelsView: View {
    @EnvironmentObject var modelManager: ModelManager

    private var streamedModels: [AIModel] {
        modelManager.availableModels.filter { $0.engineFormat == .swiftlet }
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
                LazyVStack(spacing: 20) {
                    heroCard

                    ForEach(streamedModels) { model in
                        ModelCardView(model: model)
                    }

                    if let err = modelManager.downloadError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    expectationsCard
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Experimental Models")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Models bigger than your phone")
                .font(.title3.weight(.semibold))
            Text("Streamed models keep only a small core in memory and read the rest from storage as they think. That is how a 35-billion-parameter model runs on an iPhone in about 2.5 GB of RAM. Downloads come straight from Hugging Face and are resumable.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var expectationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What to expect (early beta)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            expectationRow("clock", "The first reply takes about 30 seconds to start on iPhone 17. Replies stream at about 1 token per second. We are actively making this faster.")
            expectationRow("plus.bubble", "Long conversations slow down. Start a New Chat to stay fast.")
            expectationRow("bubble.left.and.bubble.right", "Chat only for now. Health, Finance, and Journal features need a smaller model (like Qwen 2.5 1.5B). Download one alongside.")
            expectationRow("internaldrive", "Needs about 18 GB of free storage. Memory stays low because the model streams from storage.")
            expectationRow("wifi", "The 18 GB download can take an hour or more; Hugging Face limits anonymous download speed. Keep the app open while it runs. If it stops, tap Download again and it continues where it left off.")
            expectationRow("hammer", "This feature is very new. Quality and speed will improve with updates. Thanks for trying it early.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func expectationRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
