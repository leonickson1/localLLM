//
//  TermsOfServiceView.swift
//  LocalLLM
//
//  Onboarding: 3 clean pages, minimal text.
//

import SwiftUI

struct TermsOfServiceView: View {
    @Binding var showTerms: Bool
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background matching the rest of the app
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            GridPattern(spacing: 30, lineWidth: 1)
                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.03))
                .ignoresSafeArea()
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [(colorScheme == .dark ? Color.blue : Color.indigo).opacity(0.1), .clear],
                            center: .center, startRadius: 0,
                            endRadius: proxy.size.width * 0.8
                        )
                    )
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                    .position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.15)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingWelcome().tag(0)
                    OnboardingPrivacy().tag(1)
                    OnboardingStart(onAccept: { appState.acceptTerms() }).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Dots + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.primary : Color.primary.opacity(0.15))
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    if currentPage < 2 {
                        Button {
                            withAnimation(.easeInOut) { currentPage += 1 }
                        } label: {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Page 1: Welcome

struct OnboardingWelcome: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 120)

            // 8-point star matching app icon
            AppLogoView(size: 80)

            Spacer().frame(height: 40)

            Text("Local Intelligence")
                .font(.system(size: 34, weight: .bold))
                .padding(.bottom, 12)

            Text("AI that runs entirely on your device.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Page 2: Privacy + Features

struct OnboardingPrivacy: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 120)

            Text("Private by design.")
                .font(.system(size: 30, weight: .bold))
                .padding(.bottom, 40)

            VStack(spacing: 24) {
                OnboardingRow(icon: "lock.shield.fill", color: .green,
                              text: "Stays on your device")

                OnboardingRow(icon: "heart.fill", color: .pink,
                              text: "Health analyzed locally")

                OnboardingRow(icon: "creditcard.fill", color: .blue,
                              text: "Finances never uploaded")

                OnboardingRow(icon: "wifi.slash", color: .orange,
                              text: "Works offline")

                OnboardingRow(icon: "server.rack", color: .indigo,
                              text: "Optional Ollama for big models")
            }
            .padding(.horizontal, 36)

            Spacer()
        }
    }
}

struct OnboardingRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 32, alignment: .center)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Page 3: Disclaimers + Start

struct OnboardingStart: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 120)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .padding(.bottom, 28)

            Text("Almost ready.")
                .font(.system(size: 30, weight: .bold))
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 18) {
                DisclaimerLine(text: "AI may make mistakes")
                DisclaimerLine(text: "Not medical or financial advice")
                DisclaimerLine(text: "No tracking, no telemetry")
            }
            .padding(.horizontal, 36)

            Spacer()

            Text("By continuing, you agree to our Privacy Policy & Terms of Use.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 8)

            Button(action: onAccept) {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

struct DisclaimerLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
                .padding(.top, 8)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}
