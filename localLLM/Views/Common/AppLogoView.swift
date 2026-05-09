//
//  AppLogoView.swift
//  LocalLLM
//
//  8-point star matching the app icon.
//

import SwiftUI

struct AppLogoView: View {
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            // Vertical
            Capsule()
                .fill(.primary)
                .frame(width: size * 0.09, height: size)
            // Horizontal
            Capsule()
                .fill(.primary)
                .frame(width: size, height: size * 0.09)
            // Diagonal TL-BR
            Capsule()
                .fill(.primary)
                .frame(width: size * 0.09, height: size * 0.72)
                .rotationEffect(.degrees(45))
            // Diagonal TR-BL
            Capsule()
                .fill(.primary)
                .frame(width: size * 0.09, height: size * 0.72)
                .rotationEffect(.degrees(-45))
        }
        .frame(width: size, height: size)
    }
}
