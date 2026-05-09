//
//  HealthView.swift
//  LocalLLM
//
//  Health dashboard with AI insights, arc gauges, and bento metrics.
//

import SwiftUI

struct HealthView: View {
    let model: AIModel
    @EnvironmentObject var healthManager: HealthManager
    @State private var connectionError: String?

    var body: some View {
        ZStack {
            if healthManager.isAuthorized {
                HealthDashboardView()
            } else {
                HealthConnectView(connectionError: $connectionError)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Connect View

struct HealthConnectView: View {
    @EnvironmentObject var healthManager: HealthManager
    @Binding var connectionError: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background with grid + pink ambient glow
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            GridPattern(spacing: 30, lineWidth: 1)
                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.03))
                .ignoresSafeArea()
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.pink.opacity(0.12), .clear],
                            center: .center, startRadius: 0,
                            endRadius: proxy.size.width * 0.7
                        )
                    )
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.3)
            }
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(Color.pink.opacity(0.08)).frame(width: 140, height: 140)
                        Circle().stroke(Color.pink.opacity(0.15), lineWidth: 1).frame(width: 140, height: 140)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 52)).foregroundStyle(.pink)
                    }

                    Text("Health Intelligence")
                        .font(.system(size: 28, weight: .heavy)).tracking(-0.5)

                    Text("Sync with Apple Health for AI coaching,\nsleep analysis, and activity trends.")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(3)
                        .padding(.horizontal, 32)
                }

                if let error = connectionError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    Task {
                        do {
                            try await healthManager.requestAuthorization()
                        } catch { connectionError = "Failed: \(error.localizedDescription)" }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Health Data")
                    }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 40)
            }
        }
    }
}

// MARK: - Dashboard

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var ollamaService: OllamaService
    @State private var navigateToChat = false
    @State private var animateGauges = false
    @State private var aiInsightText: String = ""
    @State private var isGeneratingInsight = false
    @State private var isRefreshing = false
    @State private var showDisconnectAlert = false
    @State private var showInsightCitations = false

    // Quick rule-based insight (always available, instant)
    private var quickInsight: String {
        var insights: [String] = []

        if healthManager.sleepChange > 0.5 {
            insights.append("You slept \(Int(healthManager.sleepChange * 60)) min more than yesterday")
        } else if healthManager.sleepChange < -0.5 {
            insights.append("Sleep was \(Int(abs(healthManager.sleepChange) * 60)) min less than yesterday")
        }

        if healthManager.stepsChange > 1000 {
            insights.append("Steps are up by \(healthManager.stepsChange.formatted())")
        } else if healthManager.stepsChange < -1000 {
            insights.append("Steps are down \(abs(healthManager.stepsChange).formatted()) from yesterday")
        }

        let movePercent = Int(healthManager.moveProgress * 100)
        if movePercent >= 80 {
            insights.append("Almost at your move goal (\(movePercent)%)")
        } else if movePercent < 30 {
            insights.append("Move goal at \(movePercent)% - get moving!")
        }

        if healthManager.heartRate > 100 {
            insights.append("Heart rate is elevated at \(Int(healthManager.heartRate)) bpm")
        }

        if insights.isEmpty {
            return "Your health data is looking steady today. Keep it up."
        }
        return insights.joined(separator: ". ") + "."
    }

    private func generateAIInsight() async {
        let healthContext = healthManager.healthContextString()
        guard !healthContext.isEmpty else { return }

        let prompt = "Give a brief 2-3 sentence health insight based on this data. Be encouraging and specific. No disclaimers.\n\n\(healthContext)"

        isGeneratingInsight = true

        if ollamaService.isEnabled && ollamaService.isConnected {
            if let response = await ollamaService.chat(
                systemPrompt: "You are a concise health coach. Give brief, actionable insights in 2-3 sentences.",
                userMessage: prompt
            ) {
                aiInsightText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if inferenceManager.isModelLoaded {
            let formatted = PromptFormatter.format(
                systemPrompt: .healthCoach(healthContext: healthContext),
                messages: [MessageTurn(role: "user", content: "Give me a brief 2-3 sentence insight about my health today.")],
                template: .chatml
            )
            let stream = inferenceManager.generate(prompt: formatted, parameters: parameterStore.asModelParameters)
            var result = ""
            for await token in stream { result += token }
            if !result.isEmpty {
                aiInsightText = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        isGeneratingInsight = false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HEALTH")
                            .font(.system(size: 12, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(Date().formatted(date: .long, time: .omitted))
                            .font(.system(size: 28, weight: .heavy)).tracking(-0.5)
                    }
                    .padding(.horizontal)

                    // Quick Insight (rule-based, always shows)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Circle())

                        Text(quickInsight)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.9))
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(uiColor: .secondarySystemGroupedBackground), Color(uiColor: .tertiarySystemGroupedBackground)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(
                                        LinearGradient(colors: [.pink.opacity(0.3), .purple.opacity(0.1), .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .padding(.horizontal)

                    // AI-Generated Insight (below quick insight, only when available)
                    if isGeneratingInsight || !aiInsightText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                if isGeneratingInsight {
                                    ProgressView().controlSize(.mini)
                                }
                                Text(isGeneratingInsight ? "AI is analyzing your data..." : "AI Insight")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !isGeneratingInsight {
                                    Button {
                                        aiInsightText = ""
                                        Task { await generateAIInsight() }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if !aiInsightText.isEmpty {
                                Text(aiInsightText)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)

                                // Citations & disclaimer (collapsible)
                                Divider().padding(.vertical, 6)

                                Button {
                                    withAnimation { showInsightCitations.toggle() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                        Text("Not medical advice. Sources & disclaimers")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: showInsightCitations ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                if showInsightCitations {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Sources:")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Link("CDC Physical Activity Guidelines",
                                             destination: URL(string: "https://www.cdc.gov/physicalactivity/basics/adults/index.htm")!)
                                            .font(.system(size: 11))
                                        Link("WHO Physical Activity Recommendations",
                                             destination: URL(string: "https://www.who.int/news-room/fact-sheets/detail/physical-activity")!)
                                            .font(.system(size: 11))
                                        Link("CDC Sleep Recommendations",
                                             destination: URL(string: "https://www.cdc.gov/sleep/about_sleep/how_much_sleep.html")!)
                                            .font(.system(size: 11))
                                        Link("AHA Heart Rate Guidelines",
                                             destination: URL(string: "https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates")!)
                                            .font(.system(size: 11))
                                        Text("Always consult a qualified healthcare provider for medical decisions.")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 4)
                                    }
                                    .padding(.top, 6)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal)
                    }

                    // Activity Gauges
                    VStack(spacing: 16) {
                        ArcGauge(
                            label: "Move",
                            value: healthManager.activeCalories,
                            goal: healthManager.moveGoal,
                            unit: "kcal",
                            gradient: [Color(red: 1, green: 0.22, blue: 0.37), .orange],
                            icon: "flame.fill",
                            animate: animateGauges
                        )
                        ArcGauge(
                            label: "Exercise",
                            value: Double(healthManager.exerciseMinutes),
                            goal: healthManager.exerciseGoal,
                            unit: "min",
                            gradient: [.green, .yellow],
                            icon: "figure.run",
                            animate: animateGauges
                        )
                        ArcGauge(
                            label: "Stand",
                            value: Double(healthManager.standHours),
                            goal: healthManager.standGoal,
                            unit: "hrs",
                            gradient: [.blue, .cyan],
                            icon: "arrow.up.heart.fill",
                            animate: animateGauges
                        )
                    }
                    .padding(20)
                    .background(BentoBackground())
                    .padding(.horizontal)

                    // Heart Rate
                    HeartRateBentoCard(
                        current: Int(healthManager.heartRate),
                        resting: Int(healthManager.restingHeartRate)
                    )
                    .padding(.horizontal)

                    // Metrics Grid
                    HStack(spacing: 16) {
                        MetricBentoCard(icon: "figure.walk", iconColor: .orange, label: "Steps",
                                        value: healthManager.steps.formatted(), unit: nil,
                                        change: healthManager.stepsChange, isPositiveGood: true)
                        MetricBentoCard(icon: "bed.double.fill", iconColor: .purple, label: "Sleep",
                                        value: "\(Int(healthManager.sleepHours))h",
                                        unit: "\(Int((healthManager.sleepHours.truncatingRemainder(dividingBy: 1)) * 60))m",
                                        change: Int(healthManager.sleepChange * 60), isPositiveGood: true)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        MetricBentoCard(icon: "map.fill", iconColor: .blue, label: "Distance",
                                        value: String(format: "%.1f", healthManager.distance), unit: "km",
                                        change: Int(healthManager.distanceChange * 10), isPositiveGood: true)
                        MetricBentoCard(icon: "flame.fill", iconColor: .red, label: "Calories",
                                        value: "\(Int(healthManager.activeCalories))", unit: "kcal",
                                        change: Int(healthManager.caloriesChange), isPositiveGood: true)
                    }
                    .padding(.horizontal)

                    // Weekly Chart with trend selector
                    WeeklyTrendCard(healthManager: healthManager)
                        .padding(.horizontal)

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .background(Color(uiColor: .systemBackground))

            // Floating AI Button
            Button { navigateToChat = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Ask Health Coach")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(
                    Capsule().fill(Color(uiColor: .darkGray))
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            }
            .padding(.bottom, 30)
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatView(model: modelManager.downloadedModels.first ?? AIModel.sampleModels[0], initialContext: .health)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            isRefreshing = true
                            await healthManager.fetchAllData()
                            isRefreshing = false
                            aiInsightText = ""
                            await generateAIInsight()
                        }
                    } label: {
                        Label("Refresh Data", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        showDisconnectAlert = true
                    } label: {
                        Label("Disconnect Health", systemImage: "heart.slash")
                    }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Disconnect Health?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                healthManager.disconnect()
            }
        } message: {
            Text("This will clear your health data from the app. You can reconnect anytime.")
        }
        .task {
            await healthManager.fetchAllData()
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) { animateGauges = true }
            await generateAIInsight()
        }
    }
}

// MARK: - Arc Gauge (replaces Apple-style rings)

struct ArcGauge: View {
    let label: String
    let value: Double
    let goal: Double
    let unit: String
    let gradient: [Color]
    let icon: String
    let animate: Bool

    private var progress: Double { min(value / goal, 1.0) }
    private var displayProgress: Double { animate ? progress : 0 }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(gradient.first ?? .white)
                .frame(width: 36, height: 36)
                .background(gradient.first?.opacity(0.15) ?? .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Label + value
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(value))")
                        .font(.system(size: 20, weight: .bold))
                    Text("/ \(Int(goal)) \(unit)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Percentage
            Text("\(Int(progress * 100))%")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(progress >= 1.0 ? .green : .secondary)
        }

        // Progress bar
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 10)

                // Fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * displayProgress, height: 10)
                    .shadow(color: (gradient.first ?? .white).opacity(0.5), radius: displayProgress > 0 ? 8 : 0)
                    .animation(.easeOut(duration: 1.2), value: displayProgress)

                // Glow dot at the end
                if displayProgress > 0.05 {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .shadow(color: .white, radius: 4)
                        .offset(x: geo.size.width * displayProgress - 5)
                        .animation(.easeOut(duration: 1.2), value: displayProgress)
                }
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Heart Rate Card

struct HeartRateBentoCard: View {
    let current: Int
    let resting: Int

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 22)).foregroundStyle(.red)
                Text("Heart Rate").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(current > 0 ? "\(current)" : "--").font(.system(size: 28, weight: .bold))
                    Text("bpm").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 22)).foregroundStyle(.pink.opacity(0.6))
                Text("Resting Avg").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(resting > 0 ? "\(resting)" : "--").font(.system(size: 28, weight: .bold))
                    Text("bpm").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
        }
        .padding(24)
        .background(
            BentoBackground()
                .overlay(
                    RadialGradient(colors: [Color.red.opacity(0.08), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                )
        )
    }
}

// MARK: - Metric Card

struct MetricBentoCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String?
    let change: Int?
    let isPositiveGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 26, weight: .bold))
                    if let unit { Text(unit).font(.system(size: 16)).foregroundStyle(.secondary) }
                }
            }
            if let change, change != 0 {
                let isGood = isPositiveGood ? change > 0 : change < 0
                HStack(spacing: 4) {
                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(abs(change))").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isGood ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .foregroundStyle(isGood ? .green : .red)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(BentoBackground())
    }
}

// MARK: - Weekly Trend Card (with selector)

struct WeeklyTrendCard: View {
    @ObservedObject var healthManager: HealthManager
    @State private var selectedTrend = 0

    private let trends = ["Steps", "Calories", "Sleep", "Distance"]
    private let colors: [Color] = [.pink, .orange, .purple, .blue]

    private var trendData: [DailyMetric] {
        switch selectedTrend {
        case 0: return healthManager.weeklySteps
        case 1: return healthManager.weeklyCalories
        case 2: return healthManager.weeklySleep
        case 3: return healthManager.weeklyDistance
        default: return healthManager.weeklySteps
        }
    }

    private var unit: String {
        switch selectedTrend {
        case 0: return "steps"
        case 1: return "kcal"
        case 2: return "hours"
        case 3: return "km"
        default: return ""
        }
    }

    private var avg: String {
        guard !trendData.isEmpty else { return "0" }
        let avgVal = trendData.map(\.value).reduce(0, +) / Double(trendData.count)
        if selectedTrend == 2 || selectedTrend == 3 {
            return String(format: "%.1f", avgVal)
        }
        return Int(avgVal).formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Trends")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg).font(.system(size: 26, weight: .bold))
                    Text("\(unit) avg").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }

            // Trend selector pills
            HStack(spacing: 8) {
                ForEach(0..<trends.count, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTrend = i }
                    } label: {
                        Text(trends[i])
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(selectedTrend == i ? colors[i] : Color.primary.opacity(0.06))
                            .foregroundStyle(selectedTrend == i ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                }
            }

            // Chart
            if trendData.isEmpty {
                Text("No data available")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(height: 120).frame(maxWidth: .infinity)
            } else {
                let maxVal = trendData.map(\.value).max() ?? 1
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(trendData) { metric in
                        VStack(spacing: 6) {
                            // Value on top
                            Text(selectedTrend == 2 || selectedTrend == 3
                                 ? String(format: "%.1f", metric.value)
                                 : "\(Int(metric.value))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(metric.date.isToday ? colors[selectedTrend] : .secondary)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    metric.date.isToday
                                    ? LinearGradient(colors: [colors[selectedTrend], colors[selectedTrend].opacity(0.3)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [.primary.opacity(0.1), .primary.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: max(4, CGFloat(metric.value / maxVal) * 90))
                                .shadow(color: metric.date.isToday ? colors[selectedTrend].opacity(0.4) : .clear, radius: 8)

                            Text(metric.dayLabel)
                                .font(.system(size: 11, weight: metric.date.isToday ? .bold : .medium))
                                .foregroundStyle(metric.date.isToday ? .primary : .secondary)
                        }
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(24)
        .background(BentoBackground())
    }
}

// MARK: - Weekly Chart (simple, used by Finance)

struct WeeklyChartBentoCard: View {
    let data: [DailyMetric]
    let label: String
    let color: Color

    private var avg: Int {
        guard !data.isEmpty else { return 0 }
        return Int(data.map(\.value).reduce(0, +) / Double(data.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(avg.formatted()).font(.system(size: 26, weight: .bold))
                        Text("avg").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if data.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.tertiary).frame(height: 120)
            } else {
                let maxVal = data.map(\.value).max() ?? 1
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(data) { metric in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    metric.date.isToday
                                    ? LinearGradient(colors: [color, color.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [.primary.opacity(0.1), .primary.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: max(4, CGFloat(metric.value / maxVal) * 100))
                                .shadow(color: metric.date.isToday ? color.opacity(0.4) : .clear, radius: 8)
                            Text(metric.dayLabel)
                                .font(.system(size: 11, weight: metric.date.isToday ? .bold : .medium))
                                .foregroundStyle(metric.date.isToday ? .primary : .secondary)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(24)
        .background(BentoBackground())
    }
}

// MARK: - Shared

struct BentoBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
