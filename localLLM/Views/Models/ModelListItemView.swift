//
//  ModelListItemView.swift
//  LocalLLM
//
//

import SwiftUI

struct ModelListItemView: View {
    let model: AIModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Model Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "cube.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            // Model Info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(model.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if model.isDownloaded {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                            Text("Ready")
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    ModelListItemView(model: AIModel.sampleModels[0])
        .padding()
        .background(Color(.systemGroupedBackground))
}

