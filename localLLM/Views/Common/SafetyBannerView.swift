//
//  SafetyBannerView.swift
//  LocalLLM
//
//  Reusable safety warning banner shown when battery/thermal/memory issues are detected.
//

import SwiftUI

struct SafetyBannerView: View {
    @EnvironmentObject var inferenceManager: InferenceManager

    var body: some View {
        if let warning = inferenceManager.safetyWarning {
            HStack(spacing: 10) {
                Image(systemName: warning.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(warning.isBlocking ? .red : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.title)
                        .font(.caption.bold())
                        .foregroundStyle(warning.isBlocking ? .red : .primary)

                    Text(warning.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    withAnimation {
                        inferenceManager.safetyWarning = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(warning.isBlocking ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(warning.isBlocking ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        // Memory unload notice
        if inferenceManager.wasUnloadedForMemory && !inferenceManager.isModelLoaded {
            HStack(spacing: 10) {
                Image(systemName: "memorychip")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)

                Text("Model was unloaded to free memory. It will reload when you send a message.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
            )
            .padding(.horizontal)
        }
    }
}
