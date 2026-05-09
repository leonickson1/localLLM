//
//  TechBackground.swift
//  LocalLLM
//
//  Shared background component.
//

import SwiftUI

struct TechBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            
            // subtle noise or mesh
            if colorScheme == .dark {
                 GridPattern(spacing: 30, lineWidth: 1)
                    .stroke(Color.white.opacity(0.03))
            } else {
                 GridPattern(spacing: 30, lineWidth: 1)
                    .stroke(Color.black.opacity(0.03))
            }
            
            // Ambient light
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (colorScheme == .dark ? Color.blue : Color.indigo).opacity(0.1),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.8
                        )
                    )
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                    .position(x: proxy.size.width * 0.2, y: proxy.size.height * 0.1)
            }
        }
    }
}

struct GridPattern: Shape {
    let spacing: CGFloat
    let lineWidth: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        for x in stride(from: 0, through: rect.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        for y in stride(from: 0, through: rect.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}
