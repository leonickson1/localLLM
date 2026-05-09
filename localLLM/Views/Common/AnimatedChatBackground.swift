//
//  AnimatedChatBackground.swift
//  LocalLLM
//
//
//

import SwiftUI

struct AnimatedChatBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var lightPosition1 = CGPoint(x: 0, y: 0)
    @State private var lightPosition2 = CGPoint(x: 1, y: 1)
    @State private var lightPosition3 = CGPoint(x: 0.5, y: 0.5)
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            
            // Grid Pattern
            GeometryReader { geometry in
                ZStack {
                    if colorScheme == .dark {
                        GridPattern(spacing: 30, lineWidth: 1)
                            .stroke(Color.white.opacity(0.05))
                    } else {
                        GridPattern(spacing: 30, lineWidth: 1)
                            .stroke(Color.black.opacity(0.05))
                    }
                    
                    // Moving light 1
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.3),
                                    Color.blue.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .position(
                            x: geometry.size.width * lightPosition1.x,
                            y: geometry.size.height * lightPosition1.y
                        )
                        .blur(radius: 20)
                    
                    // Moving light 2
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.purple.opacity(0.25),
                                    Color.purple.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .position(
                            x: geometry.size.width * lightPosition2.x,
                            y: geometry.size.height * lightPosition2.y
                        )
                        .blur(radius: 15)
                    
                    // Moving light 3
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.indigo.opacity(0.2),
                                    Color.indigo.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .position(
                            x: geometry.size.width * lightPosition3.x,
                            y: geometry.size.height * lightPosition3.y
                        )
                        .blur(radius: 18)
                    
                }
            }
        }
        .onAppear {
            animateLights()
        }
    }
    
    func animateLights() {
        // Slow-moving lights
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            lightPosition1 = CGPoint(x: 0.8, y: 0.7)
        }
        
        withAnimation(.easeInOut(duration: 25).repeatForever(autoreverses: true).delay(0.5)) {
            lightPosition2 = CGPoint(x: 0.2, y: 0.3)
        }
        
        withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true).delay(1)) {
            lightPosition3 = CGPoint(x: 0.6, y: 0.8)
        }
    }
}


