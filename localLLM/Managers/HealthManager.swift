//
//  HealthManager.swift
//  LocalLLM
//
//  Queries HealthKit for real health data and provides context for AI analysis.
//  HealthKit is optional - if not available or not entitled, falls back gracefully.
//

import Foundation
import Combine

#if canImport(HealthKit)
import HealthKit
#endif

struct DailyMetric: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

@MainActor
class HealthManager: ObservableObject {
    @Published var isAuthorized: Bool {
        didSet { UserDefaults.standard.set(isAuthorized, forKey: "health_authorized") }
    }

    // Today's metrics
    @Published var steps: Int = 0
    @Published var distance: Double = 0
    @Published var flightsClimbed: Int = 0
    @Published var sleepHours: Double = 0
    @Published var exerciseMinutes: Int = 0
    @Published var activeCalories: Double = 0
    @Published var standHours: Int = 0
    @Published var restingHeartRate: Double = 0
    @Published var heartRate: Double = 0

    // Yesterday's metrics
    @Published var yesterdaySteps: Int = 0
    @Published var yesterdayDistance: Double = 0
    @Published var yesterdayCalories: Double = 0
    @Published var yesterdaySleep: Double = 0
    @Published var yesterdayExercise: Int = 0

    // Weekly trends
    @Published var weeklySteps: [DailyMetric] = []
    @Published var weeklyCalories: [DailyMetric] = []
    @Published var weeklySleep: [DailyMetric] = []
    @Published var weeklyDistance: [DailyMetric] = []

    // Goals
    let moveGoal: Double = 600
    let exerciseGoal: Double = 45
    let standGoal: Double = 12

    var moveProgress: Double { min(activeCalories / moveGoal, 1.0) }
    var exerciseProgress: Double { min(Double(exerciseMinutes) / exerciseGoal, 1.0) }
    var standProgress: Double { min(Double(standHours) / standGoal, 1.0) }

    var stepsChange: Int { steps - yesterdaySteps }
    var caloriesChange: Double { activeCalories - yesterdayCalories }
    var sleepChange: Double { sleepHours - yesterdaySleep }
    var distanceChange: Double { distance - yesterdayDistance }
    var exerciseChange: Int { exerciseMinutes - yesterdayExercise }

    init() {
        let saved = UserDefaults.standard.bool(forKey: "health_authorized")
        self._isAuthorized = Published(initialValue: saved)
        print("[HealthManager] init - isAuthorized from UserDefaults: \(saved)")
        checkAuthOnLaunch()
    }

    private func checkAuthOnLaunch() {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }
        // Note: authorizationStatus(for:) only reports WRITE permission.
        // For read-only access, HealthKit hides the actual status for privacy.
        // We trust our persisted flag from a successful requestAuthorization().
        if isAuthorized {
            print("[HealthManager] Previously authorized - auto-fetching")
            Task {
                await fetchAllData()
            }
        }
        #endif
    }

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func disconnect() {
        isAuthorized = false
        steps = 0; distance = 0; flightsClimbed = 0; sleepHours = 0
        exerciseMinutes = 0; activeCalories = 0; standHours = 0
        heartRate = 0; restingHeartRate = 0
        yesterdaySteps = 0; yesterdayDistance = 0; yesterdayCalories = 0
        yesterdaySleep = 0; yesterdayExercise = 0
        weeklySteps = []; weeklyCalories = []; weeklySleep = []; weeklyDistance = []
        print("[HealthManager] Disconnected - cleared all data")
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleStandTime),
            HKCategoryType(.appleStandHour),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis)
        ]

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
        await fetchAllData()
    }

    func fetchAllData() async {
        print("[HealthManager] Fetching all health data...")
        await fetchTodayMetrics()
        await fetchYesterdayMetrics()
        await fetchWeeklyTrends()
        print("[HealthManager] Fetch complete")
    }

    func fetchTodayMetrics() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        async let s = fetchSum(type: .stepCount, predicate: predicate, unit: .count())
        async let d = fetchSum(type: .distanceWalkingRunning, predicate: predicate, unit: HKUnit.meterUnit(with: .kilo))
        async let f = fetchSum(type: .flightsClimbed, predicate: predicate, unit: .count())
        async let e = fetchSum(type: .appleExerciseTime, predicate: predicate, unit: .minute())
        async let c = fetchSum(type: .activeEnergyBurned, predicate: predicate, unit: .kilocalorie())
        async let st = fetchStandHours(predicate: predicate)
        async let hr = fetchLatest(type: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let rhr = fetchLatest(type: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))

        let (stepsVal, distVal, flightsVal, exerciseVal, calVal, standVal, hrVal, rhrVal) = await (s, d, f, e, c, st, hr, rhr)

        steps = Int(stepsVal)
        distance = distVal
        flightsClimbed = Int(flightsVal)
        exerciseMinutes = Int(exerciseVal)
        activeCalories = calVal
        standHours = standVal
        heartRate = hrVal
        restingHeartRate = rhrVal
        sleepHours = await fetchSleepHours(for: Date())
    }

    func fetchYesterdayMetrics() async {
        let calendar = Calendar.current
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())),
              let yesterdayEnd = calendar.date(byAdding: .day, value: 1, to: yesterdayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: yesterdayStart, end: yesterdayEnd, options: .strictStartDate)

        async let s = fetchSum(type: .stepCount, predicate: predicate, unit: .count())
        async let d = fetchSum(type: .distanceWalkingRunning, predicate: predicate, unit: HKUnit.meterUnit(with: .kilo))
        async let c = fetchSum(type: .activeEnergyBurned, predicate: predicate, unit: .kilocalorie())
        async let e = fetchSum(type: .appleExerciseTime, predicate: predicate, unit: .minute())

        let (stepsVal, distVal, calVal, exerciseVal) = await (s, d, c, e)

        yesterdaySteps = Int(stepsVal)
        yesterdayDistance = distVal
        yesterdayCalories = calVal
        yesterdayExercise = Int(exerciseVal)
        yesterdaySleep = await fetchSleepHours(for: yesterdayStart)
    }

    func fetchWeeklyTrends() async {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) else { return }

        var stepsData: [DailyMetric] = []
        var calData: [DailyMetric] = []
        var sleepData: [DailyMetric] = []
        var distData: [DailyMetric] = []

        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            async let s = fetchSum(type: .stepCount, predicate: predicate, unit: .count())
            async let c = fetchSum(type: .activeEnergyBurned, predicate: predicate, unit: .kilocalorie())
            async let d = fetchSum(type: .distanceWalkingRunning, predicate: predicate, unit: HKUnit.meterUnit(with: .kilo))
            let sl = await fetchSleepHours(for: dayStart)

            let (stepsVal, calVal, distVal) = await (s, c, d)

            stepsData.append(DailyMetric(date: dayStart, value: stepsVal))
            calData.append(DailyMetric(date: dayStart, value: calVal))
            sleepData.append(DailyMetric(date: dayStart, value: sl))
            distData.append(DailyMetric(date: dayStart, value: distVal))
        }

        weeklySteps = stepsData
        weeklyCalories = calData
        weeklySleep = sleepData
        weeklyDistance = distData
    }

    // MARK: - Query Helpers

    private func fetchSum(type: HKQuantityTypeIdentifier, predicate: NSPredicate, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let quantityType = HKQuantityType(type)
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatest(type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let quantityType = HKQuantityType(type)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: 0)
                }
            }
            healthStore.execute(query)
        }
    }

    private func fetchStandHours(predicate: NSPredicate) async -> Int {
        await withCheckedContinuation { continuation in
            let standType = HKCategoryType(.appleStandHour)
            let query = HKSampleQuery(sampleType: standType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                // Each sample with value == stood counts as one stand hour
                let count = (samples as? [HKCategorySample])?.filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count ?? 0
                continuation.resume(returning: count)
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepHours(for date: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let dayStart = calendar.date(byAdding: .hour, value: -12, to: calendar.startOfDay(for: date)) ?? date
            let dayEnd = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: date)) ?? date
            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            let sleepType = HKCategoryType(.sleepAnalysis)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var totalSleep: TimeInterval = 0
                if let categorySamples = samples as? [HKCategorySample] {
                    for sample in categorySamples {
                        if sample.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                            totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                        }
                    }
                }
                continuation.resume(returning: totalSleep / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    #else
    // Fallback when HealthKit is not available (simulator without entitlement, etc.)
    var isAvailable: Bool { false }

    func disconnect() {
        isAuthorized = false
    }

    func requestAuthorization() async throws {
        // HealthKit not available
    }

    func fetchAllData() async {}
    func fetchTodayMetrics() async {}
    func fetchYesterdayMetrics() async {}
    func fetchWeeklyTrends() async {}
    #endif

    // MARK: - Context for LLM

    func healthContextString() -> String {
        var ctx = """
        User's health data for today:
        - Steps: \(steps)\(changeStr(stepsChange, suffix: " vs yesterday"))
        - Distance: \(String(format: "%.1f", distance)) km\(changeStr(distanceChange, format: "%.1f", suffix: " km vs yesterday"))
        - Flights climbed: \(flightsClimbed)
        - Active calories: \(Int(activeCalories)) kcal\(changeStr(Int(caloriesChange), suffix: " vs yesterday"))
        - Exercise: \(exerciseMinutes) minutes\(changeStr(exerciseChange, suffix: " min vs yesterday"))
        - Stand hours: \(standHours)
        - Sleep last night: \(String(format: "%.1f", sleepHours)) hours\(changeStr(sleepChange, format: "%.1f", suffix: "h vs night before"))
        """

        if heartRate > 0 { ctx += "\n- Latest heart rate: \(Int(heartRate)) bpm" }
        if restingHeartRate > 0 { ctx += "\n- Resting heart rate: \(Int(restingHeartRate)) bpm" }

        ctx += "\n\nWeekly step trend: \(weeklySteps.map { "\($0.dayLabel): \(Int($0.value))" }.joined(separator: ", "))"
        ctx += "\nWeekly sleep trend: \(weeklySleep.map { "\($0.dayLabel): \(String(format: "%.1f", $0.value))h" }.joined(separator: ", "))"
        ctx += "\nWeekly calorie trend: \(weeklyCalories.map { "\($0.dayLabel): \(Int($0.value))" }.joined(separator: ", "))"

        return ctx
    }

    private func changeStr(_ change: Int, suffix: String) -> String {
        guard change != 0 else { return "" }
        return " (\(change > 0 ? "+" : "")\(change)\(suffix))"
    }

    private func changeStr(_ change: Double, format: String = "%.0f", suffix: String) -> String {
        guard abs(change) > 0.1 else { return "" }
        return " (\(change > 0 ? "+" : "")\(String(format: format, change))\(suffix))"
    }
}
