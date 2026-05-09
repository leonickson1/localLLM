//
//  FinanceView.swift
//  LocalLLM
//
//  Finance dashboard with auto-pipeline: upload → extract → categorize → display.
//

import SwiftUI
import UniformTypeIdentifiers

struct FinanceView: View {
    let model: AIModel
    @EnvironmentObject var financeManager: FinanceManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore

    var body: some View {
        ZStack {
            if financeManager.transactions.isEmpty && !financeManager.isProcessing && !financeManager.hasProcessedStatement {
                FinanceUploadView()
            } else {
                FinanceDashboardView()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { financeManager.loadTransactions() }
    }
}

// MARK: - Upload View

struct FinanceUploadView: View {
    @EnvironmentObject var financeManager: FinanceManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var ollamaService: OllamaService
    @State private var showFileImporter = false
    @State private var showAccountPrompt = false
    @State private var pendingURLs: [URL] = []
    @State private var accountLabelInput = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background with grid + blue ambient glow
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            GridPattern(spacing: 30, lineWidth: 1)
                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.03))
                .ignoresSafeArea()
            GeometryReader { proxy in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.12), .clear],
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
                        Circle().fill(Color.blue.opacity(0.08)).frame(width: 140, height: 140)
                        Circle().stroke(Color.blue.opacity(0.15), lineWidth: 1).frame(width: 140, height: 140)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 52)).foregroundStyle(.blue)
                    }

                    Text("Finance Intelligence")
                        .font(.system(size: 28, weight: .heavy)).tracking(-0.5)

                    Text("Upload credit card or bank statements.\nAI will extract and categorize your transactions.")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(3)
                        .padding(.horizontal, 32)
                }

                if financeManager.isProcessing {
                    ProcessingCard(stage: financeManager.rawStatementText.isEmpty ? "Extracting text from PDF..." : "AI is categorizing transactions...")
                }

                Spacer()

                if !financeManager.isProcessing {
                    VStack(spacing: 16) {
                        // Model picker - let user choose before uploading
                        FinanceModelPicker()

                        Button { showFileImporter = true } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Upload Statements")
                            }
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .padding(.horizontal, 32)
                    }
                }

                Spacer().frame(height: 40)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.pdf, UTType.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                pendingURLs = urls
                showAccountPrompt = true
            }
        }
        .sheet(isPresented: $showAccountPrompt) {
            AccountLabelSheet(accountLabel: $accountLabelInput) {
                let label = accountLabelInput.isEmpty ? nil : accountLabelInput
                accountLabelInput = ""
                runFullPipeline(urls: pendingURLs, accountLabel: label)
                pendingURLs = []
            }
        }
    }

    private func runFullPipeline(urls: [URL], accountLabel: String?) {
        Task {
            for url in urls {
                financeManager.setActiveStatement(accountLabel: accountLabel)
                await financeManager.parseStatement(from: url)
                if !financeManager.rawStatementText.isEmpty {
                    await financeManager.categorizeWithLLM(
                        using: inferenceManager,
                        parameters: parameterStore.asModelParameters,
                        ollamaService: ollamaService
                    )
                }
            }
        }
    }
}

// MARK: - Account Label Sheet

struct AccountLabelSheet: View {
    @Binding var accountLabel: String
    let onContinue: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("Which account is this from?")
                    .font(.system(size: 20, weight: .bold))

                Text("Optional - helps track spending across cards")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("e.g. Chase ...4521", text: $accountLabel)
                    .font(.system(size: 16))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        accountLabel = ""
                        dismiss()
                        onContinue()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct ProcessingCard: View {
    let stage: String
    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Processing").font(.system(size: 14, weight: .semibold))
                Text(stage).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.blue.opacity(0.2), lineWidth: 1))
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Dashboard

struct FinanceDashboardView: View {
    @EnvironmentObject var financeManager: FinanceManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var parameterStore: ParameterStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var ollamaService: OllamaService
    @State private var navigateToChat = false
    @State private var showFileImporter = false
    @State private var showClearAlert = false
    @State private var showAddTransaction = false
    @State private var showEditTransaction = false
    @State private var editingTransaction: ParsedTransaction?
    @State private var showAccountPrompt = false
    @State private var pendingURLs: [URL] = []
    @State private var accountLabelInput = ""
    @State private var showFinanceCitations = false

    // Quick rule-based insight (matches Health pattern)
    private var quickInsight: String {
        var insights: [String] = []

        // Multi-statement summary
        if financeManager.statements.count > 1 {
            insights.append("Across \(financeManager.statements.count) statements")
        }

        if let top = financeManager.topCategory {
            insights.append("\(top.category) is your top category at \(Int(top.percentage * 100))% of spending")
        }

        let refundCount = financeManager.filteredTransactions.filter { $0.isRefund }.count
        if refundCount > 0 {
            let refundTotal = financeManager.filteredTransactions.filter { $0.isRefund }.reduce(0) { $0 + $1.amount }
            insights.append("\(refundCount) refund(s) totaling $\(String(format: "%.0f", refundTotal))")
        }

        if let largest = financeManager.largestTransaction {
            insights.append("Biggest expense: \(largest.merchant) at $\(String(format: "%.0f", largest.amount))")
        }

        if insights.isEmpty {
            return "\(financeManager.filteredTransactions.count) transactions totaling $\(String(format: "%.0f", financeManager.totalSpending))."
        }
        return insights.prefix(3).joined(separator: ". ") + "."
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header (matches Health)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SPENDING")
                            .font(.system(size: 12, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(Date().formatted(date: .long, time: .omitted))
                            .font(.system(size: 28, weight: .heavy)).tracking(-0.5)
                    }
                    .padding(.horizontal)

                    // Account Filter Pills
                    if financeManager.availableAccounts.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                AccountPill(label: "All", isSelected: financeManager.selectedAccount == nil) {
                                    financeManager.selectedAccount = nil
                                    financeManager.recalculateSpending()
                                }
                                ForEach(financeManager.availableAccounts, id: \.self) { account in
                                    AccountPill(label: account, isSelected: financeManager.selectedAccount == account) {
                                        financeManager.selectedAccount = account
                                        financeManager.recalculateSpending()
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Quick Insight (matches Health insight card)
                    if !financeManager.filteredTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 32, height: 32)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(Circle())

                                Text(quickInsight)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.9))
                                    .lineSpacing(3)
                            }

                            Divider().padding(.vertical, 4)

                            Button {
                                withAnimation { showFinanceCitations.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                    Text("Not financial advice. Sources & disclaimers")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: showFinanceCitations ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if showFinanceCitations {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Sources:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Link("Consumer Financial Protection Bureau",
                                         destination: URL(string: "https://www.consumerfinance.gov/")!)
                                        .font(.system(size: 11))
                                    Link("FTC Consumer Advice",
                                         destination: URL(string: "https://consumer.ftc.gov/articles/making-budget")!)
                                        .font(.system(size: 11))
                                    Link("MyMoney.gov - Federal Resource",
                                         destination: URL(string: "https://www.mymoney.gov/")!)
                                        .font(.system(size: 11))
                                    Text("AI-generated insights are for personal tracking only. Consult a qualified financial advisor for financial decisions.")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                                .padding(.top, 4)
                            }
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
                                            LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.1), .clear],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal)
                    }

                    // Multi-statement info
                    if financeManager.statements.count > 1 {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue)
                            Text("Showing combined data from \(financeManager.statements.count) statements. Upload more to build a complete picture.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Processing
                    if financeManager.isProcessing {
                        ProcessingCard(stage: financeManager.processingProgress.isEmpty
                            ? "Analyzing transactions..." : financeManager.processingProgress)
                    }

                    // Error
                    if let error = financeManager.processingError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extraction Issue")
                                    .font(.caption.bold())
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal)
                    }

                    if financeManager.transactions.isEmpty && financeManager.hasProcessedStatement && !financeManager.isProcessing {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Text("No transactions extracted")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Small models often can't parse statements accurately. Try a larger model or connect Ollama.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            // Model picker for retry
                            VStack(spacing: 10) {
                                if ollamaService.isEnabled && ollamaService.isConnected {
                                    Menu {
                                        ForEach(ollamaService.availableModels, id: \.self) { m in
                                            Button(m) { ollamaService.selectedModel = m }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "server.rack").font(.caption)
                                            Text("Ollama: \(ollamaService.selectedModel)")
                                                .font(.caption.bold())
                                        }
                                        .foregroundStyle(.green)
                                    }
                                }

                                if !modelManager.downloadedModels.isEmpty {
                                    Menu {
                                        ForEach(modelManager.downloadedModels) { m in
                                            Button(m.displayName) {
                                                Task { await inferenceManager.loadModel(m) }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "cpu").font(.caption)
                                            Text("Switch local model")
                                                .font(.caption.bold())
                                        }
                                        .foregroundStyle(.blue)
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button { showFileImporter = true } label: {
                                    HStack { Image(systemName: "arrow.clockwise"); Text("Upload Again") }
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 20).padding(.vertical, 10)
                                        .background(Color.blue).foregroundStyle(.white).clipShape(Capsule())
                                }

                                Button { showAddTransaction = true } label: {
                                    HStack { Image(systemName: "plus"); Text("Add Manually") }
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 20).padding(.vertical, 10)
                                        .background(Color.primary.opacity(0.08)).foregroundStyle(.primary).clipShape(Capsule())
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(BentoBackground())
                        .padding(.horizontal)
                    }

                    // Summary metrics (matches Health metric cards)
                    HStack(spacing: 16) {
                        MetricBentoCard(icon: "dollarsign.circle.fill", iconColor: .blue,
                                        label: "Total Spent",
                                        value: "$\(String(format: "%.0f", financeManager.totalSpending))",
                                        unit: nil, change: nil, isPositiveGood: false)
                        MetricBentoCard(icon: "divide.circle.fill", iconColor: .purple,
                                        label: "Average",
                                        value: "$\(String(format: "%.0f", financeManager.averageTransaction))",
                                        unit: "per txn", change: nil, isPositiveGood: false)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        MetricBentoCard(icon: "receipt.fill", iconColor: .green,
                                        label: "Transactions",
                                        value: "\(financeManager.filteredTransactions.count)",
                                        unit: nil, change: nil, isPositiveGood: false)
                        MetricBentoCard(icon: "doc.text.fill", iconColor: .orange,
                                        label: "Statements",
                                        value: "\(financeManager.statements.count)",
                                        unit: nil, change: nil, isPositiveGood: false)
                    }
                    .padding(.horizontal)

                    // Monthly Trend Card
                    if financeManager.monthlySpending.count > 1 {
                        MonthlyTrendCard(monthlyData: financeManager.monthlySpending)
                            .padding(.horizontal)
                    }

                    // Category Breakdown (horizontal bars matching Health gauges)
                    if !financeManager.categorySpending.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("By Category")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)

                            ForEach(financeManager.categorySpending) { cat in
                                ArcGauge(
                                    label: cat.category,
                                    value: cat.amount,
                                    goal: financeManager.totalSpending,
                                    unit: "$\(String(format: "%.0f", cat.amount))",
                                    gradient: [cat.color, cat.color.opacity(0.5)],
                                    icon: ParsedTransaction(merchant: "", date: "", amount: 0, category: cat.category).icon,
                                    animate: true
                                )
                            }
                        }
                        .padding(20)
                        .background(BentoBackground())
                        .padding(.horizontal)
                    }

                    // Transactions list
                    if !financeManager.filteredTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("All Transactions")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                Spacer()
                                // Actions inline
                                HStack(spacing: 8) {
                                    Button { showAddTransaction = true } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.blue)
                                            .frame(width: 32, height: 32)
                                            .background(Color.blue.opacity(0.08))
                                            .clipShape(Circle())
                                    }

                                    Button { showFileImporter = true } label: {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                            .background(Color.primary.opacity(0.05))
                                            .clipShape(Circle())
                                    }

                                    Menu {
                                        Button(role: .destructive) { showClearAlert = true } label: {
                                            Label("Clear All", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                            .background(Color.primary.opacity(0.05))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding(.horizontal)

                            VStack(spacing: 0) {
                                ForEach(financeManager.filteredTransactions) { transaction in
                                    FinanceTransactionRow(transaction: transaction)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingTransaction = transaction
                                            showEditTransaction = true
                                        }
                                    if transaction.id != financeManager.filteredTransactions.last?.id {
                                        Divider().padding(.leading, 72)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .background(Color(uiColor: .systemBackground))

            // Floating AI Button (matches Health)
            Button { navigateToChat = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Ask Finance AI")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
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
            ChatView(model: modelManager.downloadedModels.first ?? AIModel.sampleModels[0], initialContext: .finance)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.pdf, UTType.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                pendingURLs = urls
                showAccountPrompt = true
            }
        }
        .sheet(isPresented: $showAccountPrompt) {
            AccountLabelSheet(accountLabel: $accountLabelInput) {
                let label = accountLabelInput.isEmpty ? nil : accountLabelInput
                accountLabelInput = ""
                Task {
                    for url in pendingURLs {
                        financeManager.setActiveStatement(accountLabel: label)
                        await financeManager.parseStatement(from: url)
                        if !financeManager.rawStatementText.isEmpty {
                            await financeManager.categorizeWithLLM(using: inferenceManager, parameters: parameterStore.asModelParameters, ollamaService: ollamaService)
                        }
                    }
                    pendingURLs = []
                }
            }
        }
        .alert("Clear All Data", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                financeManager.clearAllTransactions()
            }
        } message: {
            Text("Delete all transactions? You'll need to upload statements again.")
        }
        .sheet(isPresented: $showAddTransaction) {
            TransactionEditorSheet(mode: .add) { merchant, date, amount, category in
                financeManager.addTransaction(merchant: merchant, date: date, amount: amount, category: category)
            }
        }
        .sheet(isPresented: $showEditTransaction) {
            if let transaction = editingTransaction {
                TransactionEditorSheet(mode: .edit(transaction)) { merchant, date, amount, category in
                    var updated = transaction
                    updated.merchant = merchant
                    updated.date = date
                    updated.amount = amount
                    updated.category = category
                    financeManager.updateTransaction(updated)
                }
            }
        }
    }
}

// MARK: - Transaction Editor Sheet

struct TransactionEditorSheet: View {
    enum Mode {
        case add
        case edit(ParsedTransaction)
    }

    let mode: Mode
    let onSave: (String, String, Double, String) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var merchant = ""
    @State private var date = ""
    @State private var amount = ""
    @State private var category = "Other"

    private let categories = ["Dining", "Groceries", "Transport", "Subscription", "Shopping", "Utilities", "Entertainment", "Health", "Services", "Other"]

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Merchant name", text: $merchant)
                    TextField("Date (e.g. 04/15)", text: $date)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amountVal = Double(amount), !merchant.isEmpty {
                            onSave(merchant, date, amountVal, category)
                            dismiss()
                        }
                    }
                    .disabled(merchant.isEmpty || amount.isEmpty)
                }
            }
            .onAppear {
                if case .edit(let t) = mode {
                    merchant = t.merchant
                    date = t.date
                    amount = String(format: "%.2f", t.amount)
                    category = t.category
                }
            }
        }
    }
}

// MARK: - Finance Model Picker

struct FinanceModelPicker: View {
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var modelManager: ModelManager

    private var hasOllama: Bool { ollamaService.isEnabled && ollamaService.isConnected }
    private var hasLocal: Bool { !modelManager.downloadedModels.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            if hasOllama || hasLocal {
                Menu {
                    if hasOllama {
                        Section("Ollama (recommended)") {
                            ForEach(ollamaService.availableModels, id: \.self) { m in
                                Button {
                                    ollamaService.selectedModel = m
                                } label: {
                                    HStack {
                                        Text(m)
                                        if ollamaService.selectedModel == m { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }
                    if hasLocal {
                        Section("On-Device") {
                            ForEach(modelManager.downloadedModels) { m in
                                Button {
                                    Task { await inferenceManager.loadModel(m) }
                                } label: {
                                    HStack {
                                        Text(m.displayName)
                                        if inferenceManager.currentModelId == m.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hasOllama ? .green : (inferenceManager.isModelLoaded ? .green : .orange))
                            .frame(width: 6, height: 6)

                        if hasOllama {
                            Image(systemName: "server.rack").font(.system(size: 11))
                            Text(ollamaService.selectedModel)
                                .font(.system(size: 13, weight: .medium))
                        } else if inferenceManager.isModelLoaded {
                            Image(systemName: "cpu").font(.system(size: 11))
                            Text(modelManager.downloadedModels.first(where: { $0.id == inferenceManager.currentModelId })?.displayName ?? "Local model")
                                .font(.system(size: 13, weight: .medium))
                        } else {
                            Text("Select model")
                                .font(.system(size: 13, weight: .medium))
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }

                if !hasOllama && hasLocal {
                    Text("Small models may misread transactions. For best results, connect Ollama.")
                        .font(.caption2).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text("No model available").font(.caption).foregroundStyle(.orange)
                    }
                    NavigationLink { ModelsView() } label: {
                        Text("Download a model")
                            .font(.caption.bold()).foregroundStyle(.blue)
                    }
                }
            }
        }
    }
}

// MARK: - Account Filter Pill

struct AccountPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.primary.opacity(0.06))
                .foregroundStyle(isSelected ? .white : .secondary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Monthly Trend Card

struct MonthlyTrendCard: View {
    let monthlyData: [MonthlySpending]

    private var avg: String {
        guard !monthlyData.isEmpty else { return "$0" }
        let avgVal = monthlyData.map(\.totalSpent).reduce(0, +) / Double(monthlyData.count)
        return "$\(Int(avgVal).formatted())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly Trends")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg).font(.system(size: 26, weight: .bold))
                    Text("avg/month").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }

            if monthlyData.isEmpty {
                Text("No dated transactions yet")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(height: 120).frame(maxWidth: .infinity)
            } else {
                let maxVal = monthlyData.map(\.totalSpent).max() ?? 1
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(monthlyData) { metric in
                        VStack(spacing: 6) {
                            Text("$\(Int(metric.totalSpent))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(metric.isThisMonth ? .blue : .secondary)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    metric.isThisMonth
                                    ? LinearGradient(colors: [.blue, .blue.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [.primary.opacity(0.1), .primary.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: max(4, CGFloat(metric.totalSpent / maxVal) * 90))
                                .shadow(color: metric.isThisMonth ? Color.blue.opacity(0.4) : .clear, radius: 8)

                            Text(metric.monthLabel)
                                .font(.system(size: 11, weight: metric.isThisMonth ? .bold : .medium))
                                .foregroundStyle(metric.isThisMonth ? .primary : .secondary)
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

// MARK: - Finance Components

struct FinanceTransactionRow: View {
    let transaction: ParsedTransaction

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: transaction.isRefund ? "arrow.uturn.backward.circle.fill" : transaction.icon)
                .font(.system(size: 18))
                .foregroundStyle(transaction.isRefund ? .green : transaction.color)
                .frame(width: 40, height: 40)
                .background((transaction.isRefund ? Color.green : transaction.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(transaction.category)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if transaction.isRefund {
                        Text("REFUND")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(transaction.isRefund ? "+" : "-")$\(String(format: "%.2f", transaction.amount))")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(transaction.isRefund ? .green : .primary)
                Text(transaction.date)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
