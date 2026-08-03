//
//  FinanceManager.swift
//  LocalLLM
//
//  Manages finance data: parses PDF/image statements, stores transactions locally.
//

import Foundation
import PDFKit
import SwiftUI
import Combine

struct ParsedTransaction: Identifiable, Codable {
    var id = UUID()
    var merchant: String
    var date: String
    var amount: Double
    var category: String
    var isRefund: Bool = false
    var statementId: UUID? = nil
    var accountLabel: String? = nil
    var parsedDate: Date? = nil

    var icon: String {
        switch category.lowercased() {
        case "dining", "restaurant", "food": return "fork.knife"
        case "groceries", "grocery": return "basket.fill"
        case "transport", "transportation", "uber", "lyft", "gas": return "car.fill"
        case "subscription", "streaming": return "play.tv.fill"
        case "shopping", "retail": return "bag.fill"
        case "utilities", "bills": return "bolt.fill"
        case "entertainment": return "ticket.fill"
        case "health", "medical": return "cross.fill"
        default: return "creditcard.fill"
        }
    }

    var color: Color {
        switch category.lowercased() {
        case "dining", "restaurant", "food": return .orange
        case "groceries", "grocery": return .green
        case "transport", "transportation", "uber", "lyft", "gas": return .blue
        case "subscription", "streaming": return .red
        case "shopping", "retail": return .purple
        case "utilities", "bills": return .yellow
        case "entertainment": return .pink
        case "health", "medical": return .teal
        default: return .gray
        }
    }
}

struct SpendingCategory: Identifiable {
    let id = UUID()
    let category: String
    let amount: Double
    let percentage: Double
    let color: Color
}

struct StatementInfo: Identifiable, Codable {
    var id = UUID()
    var accountLabel: String
    var uploadDate: Date
    var transactionCount: Int
    var dateRange: String
}

struct MonthlySpending: Identifiable {
    let id = UUID()
    let month: Date
    let totalSpent: Double

    var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: month)
    }

    var isThisMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }
}

@MainActor
class FinanceManager: ObservableObject {
    @Published var transactions: [ParsedTransaction] = []
    @Published var categorySpending: [SpendingCategory] = []
    @Published var totalSpending: Double = 0
    @Published var isProcessing = false
    @Published var rawStatementText = ""
    @Published var statementCount: Int = 0
    @Published var hasProcessedStatement = false
    @Published var processingError: String?
    @Published var processingProgress: String = ""
    @Published var pagesProcessed: Int = 0
    @Published var totalPages: Int = 0
    @Published var statements: [StatementInfo] = []
    @Published var monthlySpending: [MonthlySpending] = []
    @Published var selectedAccount: String? = nil

    // MARK: - Filtered & Computed Properties

    var filteredTransactions: [ParsedTransaction] {
        guard let account = selectedAccount else { return transactions }
        return transactions.filter { ($0.accountLabel ?? "Unknown") == account }
    }

    var availableAccounts: [String] {
        let labels = Set(transactions.compactMap { $0.accountLabel })
        return Array(labels).sorted()
    }

    private var purchases: [ParsedTransaction] {
        filteredTransactions.filter { !$0.isRefund }
    }

    var averageTransaction: Double {
        guard !purchases.isEmpty else { return 0 }
        let purchaseTotal = purchases.reduce(0) { $0 + $1.amount }
        return purchaseTotal / Double(purchases.count)
    }

    var largestTransaction: ParsedTransaction? {
        purchases.max(by: { $0.amount < $1.amount })
    }

    var smallestTransaction: ParsedTransaction? {
        purchases.filter { $0.amount > 0 }.min(by: { $0.amount < $1.amount })
    }

    var refundTotal: Double {
        filteredTransactions.filter { $0.isRefund }.reduce(0) { $0 + $1.amount }
    }

    var topCategory: SpendingCategory? {
        categorySpending.first
    }

    var transactionsByCategory: [String: [ParsedTransaction]] {
        Dictionary(grouping: filteredTransactions, by: { $0.category })
    }

    // MARK: - Active Statement Tracking

    private var currentStatementId: UUID?
    private var currentAccountLabel: String?
    private var currentStatementYear: Int?

    func setActiveStatement(accountLabel: String?) {
        currentStatementId = UUID()
        currentAccountLabel = accountLabel
        currentStatementYear = nil
    }

    // MARK: - PDF Parsing

    func parseStatement(from url: URL) async {
        isProcessing = true

        guard url.startAccessingSecurityScopedResource() else {
            isProcessing = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let text = try await PDFTextExtractor.extractText(from: url)
            if !text.isEmpty {
                rawStatementText = text
                statementCount += 1
                print("[FinanceManager] Extracted \(text.count) chars from PDF")
            } else {
                print("[FinanceManager] PDF extraction returned empty text")
            }
        } catch {
            print("[FinanceManager] PDF extraction error: \(error)")
        }

        isProcessing = false
    }

    // MARK: - Image OCR

    func parseStatementImage(_ image: UIImage) async {
        isProcessing = true

        do {
            let text = try await VisionTextExtractor.extractText(from: image)
            rawStatementText = text
            statementCount += 1
        } catch {
            print("OCR error: \(error)")
        }

        isProcessing = false
    }

    // MARK: - LLM Categorization

    func categorizeWithLLM(
        using inferenceManager: InferenceManager,
        parameters: AIModel.ModelParameters,
        ollamaService: OllamaService? = nil,
        openAICompat: OpenAICompatibleService? = nil
    ) async {
        guard !rawStatementText.isEmpty else {
            print("[FinanceManager] categorize called but rawStatementText is empty")
            return
        }

        print("[FinanceManager] Starting LLM categorization with \(rawStatementText.count) chars")

        // Priority 1: OpenAI-compatible (preferred for big cloud or local llama-server models)
        if let openAI = openAICompat, openAI.isEnabled && openAI.isConnected && !openAI.selectedModel.isEmpty {
            print("[FinanceManager] Using OpenAI-compatible (\(openAI.selectedModel)) for extraction")
            await categorizeWithRemote(label: "OpenAI-compat") { [weak openAI] sys, msg in
                await openAI?.chat(systemPrompt: sys, userMessage: msg)
            }
            if !transactions.isEmpty { return }
            print("[FinanceManager] OpenAI-compat returned no transactions, trying Ollama...")
        }

        // Priority 2: Ollama
        if let ollama = ollamaService, ollama.isEnabled && ollama.isConnected {
            print("[FinanceManager] Using Ollama (\(ollama.selectedModel)) for extraction")
            await categorizeWithRemote(label: "Ollama") { [weak ollama] sys, msg in
                await ollama?.chat(systemPrompt: sys, userMessage: msg)
            }
            if !transactions.isEmpty { return }
            print("[FinanceManager] Ollama returned no transactions, trying local model...")
        }

        print("[FinanceManager] Model loaded: \(inferenceManager.isModelLoaded)")

        guard inferenceManager.isModelLoaded else {
            print("[FinanceManager] No local model loaded either - cannot categorize")
            processingError = "No model available. Download a model or connect Ollama."
            isProcessing = false
            return
        }

        isProcessing = true
        hasProcessedStatement = true

        // Find the transaction section - skip headers/legal text
        let transactionText = extractTransactionSection(from: rawStatementText)
        print("[FinanceManager] Transaction section: \(transactionText.count) chars")

        // Process in chunks of ~3000 chars to handle long statements
        let chunkSize = 3000
        var allParsed: [ParsedTransaction] = []
        var offset = 0

        while offset < transactionText.count {
            let startIdx = transactionText.index(transactionText.startIndex, offsetBy: offset)
            let endOffset = min(offset + chunkSize, transactionText.count)
            let endIdx = transactionText.index(transactionText.startIndex, offsetBy: endOffset)
            let chunk = String(transactionText[startIdx..<endIdx])

            if chunk.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                offset += chunkSize
                continue
            }

            let chunkNum = (offset / chunkSize) + 1
            print("[FinanceManager] Processing chunk \(chunkNum) (\(chunk.count) chars)")

            let prompt = PromptFormatter.format(
                systemPrompt: .financeParser,
                messages: [MessageTurn(role: "user", content: chunk)],
                template: .chatml
            )

            var fullResponse = ""
            let stream = inferenceManager.generate(prompt: prompt, parameters: parameters)

            for await token in stream {
                fullResponse += token
            }

            // Parse this chunk's response - try structured first, fallback to regex
            var parsed = parseTransactionLines(fullResponse)
            if parsed.isEmpty {
                parsed = parseTransactionsFallback(fullResponse)
            }
            print("[FinanceManager] Chunk \(chunkNum): \(fullResponse.count) chars → \(parsed.count) transactions")
            allParsed.append(contentsOf: parsed)

            offset += chunkSize
        }

        print("[FinanceManager] Total parsed: \(allParsed.count) transactions from all chunks")

        // If LLM failed to parse, try regex fallback directly on the raw statement text
        if allParsed.isEmpty {
            print("[FinanceManager] LLM parsing failed - trying regex fallback on raw text")
            allParsed = parseTransactionsFallback(transactionText)
            print("[FinanceManager] Regex fallback: \(allParsed.count) transactions")
            if allParsed.isEmpty {
                processingError = "Could not extract transactions. Try a larger model (4B+) or connect Ollama for better results."
            }
        }

        if !allParsed.isEmpty {
            transactions.append(contentsOf: allParsed)
            createStatementInfo(transactionCount: allParsed.count)
            recalculateSpending()
            saveTransactions()
            saveStatements()
        }

        rawStatementText = ""
        isProcessing = false
    }

    // MARK: - Ollama Categorization (better quality with remote model)

    /// Generic remote-backend categorization. Takes a chat closure so it works with both
    /// Ollama and OpenAI-compatible backends without duplicating the page-loop logic.
    private func categorizeWithRemote(
        label: String,
        chat: @escaping (String, String) async -> String?
    ) async {
        isProcessing = true
        hasProcessedStatement = true
        processingError = nil

        let systemPrompt = SystemPrompt.financeParser.text

        // Split rawStatementText into pages (by page markers or chunks)
        let pages = rawStatementText.components(separatedBy: "\n\n").filter { $0.count > 50 }
        totalPages = max(pages.count, 1)
        pagesProcessed = 0

        print("[FinanceManager] Processing \(pages.count) sections via \(label)")

        for (i, page) in pages.enumerated() {
            pagesProcessed = i + 1
            processingProgress = "Processing section \(i + 1) of \(pages.count)..."
            print("[FinanceManager] Section \(i + 1)/\(pages.count) (\(page.count) chars)")

            // Skip very short sections (headers, footers)
            if page.count < 30 { continue }

            // Skip sections without dollar amounts
            if page.range(of: #"\$?\d+\.\d{2}"#, options: .regularExpression) == nil { continue }

            if let response = await chat(systemPrompt, page) {
                var parsed = parseTransactionLines(response)
                if parsed.isEmpty { parsed = parseTransactionsFallback(response) }
                if !parsed.isEmpty {
                    print("[FinanceManager] Section \(i + 1): found \(parsed.count) transactions")
                    transactions.append(contentsOf: parsed)
                    recalculateSpending()
                    saveTransactions()
                }
            }
        }

        let newCount = transactions.count
        print("[FinanceManager] Total: \(newCount) transactions from all sections via \(label)")

        if newCount == 0 {
            processingError = "No transactions found. Try a different model or add manually."
        } else {
            createStatementInfo(transactionCount: newCount)
            saveStatements()
        }

        if !transactions.isEmpty { rawStatementText = "" }
        processingProgress = ""
        isProcessing = false
    }

    /// Keywords that indicate non-purchase lines (payments, fees, etc.) - filter these out
    private static let skipKeywords: [String] = [
        "payment thank you", "online payment", "autopay", "automatic payment",
        "balance transfer", "interest charge", "finance charge", "late fee",
        "annual fee", "minimum payment", "previous balance", "new balance",
        "credit limit", "available credit", "cash advance", "overlimit fee",
        "returned payment", "payment received", "payment - thank"
    ]

    private func parseTransactionLines(_ response: String) -> [ParsedTransaction] {
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        var parsed: [ParsedTransaction] = []

        for line in lines {
            // Check for STATEMENT metadata line (LLM may output account/year info)
            if line.uppercased().hasPrefix("STATEMENT|") {
                let meta = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if meta.count >= 2 && !meta[1].isEmpty && currentAccountLabel == nil {
                    // Use LLM-detected account if user didn't provide one
                    let last4 = meta[1].filter { $0.isNumber }.suffix(4)
                    if !last4.isEmpty {
                        currentAccountLabel = "....\(last4)"
                    }
                }
                if meta.count >= 3, let year = Int(meta[2]) {
                    currentStatementYear = year
                }
                continue
            }

            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 4 {
                let merchantLower = parts[0].lowercased()

                // Safety net: skip payments/fees that the LLM didn't filter
                if Self.skipKeywords.contains(where: { merchantLower.contains($0) }) {
                    // Filtered non-purchase line
                    continue
                }

                let amountStr = parts[2]
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let amount = Double(amountStr), amount != 0 {
                    let isRefund = amount < 0
                        || merchantLower.contains("refund")
                        || merchantLower.contains("credit")
                        || merchantLower.contains("return")
                        || merchantLower.contains("reversal")
                        || (parts.count >= 4 && parts[3].lowercased() == "refund")

                    parsed.append(ParsedTransaction(
                        merchant: parts[0],
                        date: parts[1],
                        amount: abs(amount),
                        category: isRefund ? "Refund" : parts[3],
                        isRefund: isRefund,
                        statementId: currentStatementId,
                        accountLabel: currentAccountLabel,
                        parsedDate: Self.resolveDate(parts[1], statementYear: currentStatementYear)
                    ))
                }
            }
        }
        return parsed
    }

    /// Fallback parser: extracts transactions from freeform text or raw statement lines
    /// using regex to find date + amount patterns. Used when the LLM doesn't output structured format.
    private func parseTransactionsFallback(_ text: String) -> [ParsedTransaction] {
        var parsed: [ParsedTransaction] = []
        let lines = text.components(separatedBy: "\n")

        // Pattern: look for lines with a date-like string and a dollar amount
        // e.g. "04/15 STARBUCKS 12.50" or "Apr 15 AMAZON.COM $45.99"
        let amountPattern = #"\$?\s*(\d{1,},?\d*\.\d{2})"#
        let datePattern = #"(\d{1,2}/\d{1,2}(?:/\d{2,4})?)"#

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 10 else { continue }
            let lower = trimmed.lowercased()

            // Skip non-transaction lines
            if Self.skipKeywords.contains(where: { lower.contains($0) }) { continue }

            // Must have an amount
            guard let amountMatch = trimmed.range(of: amountPattern, options: .regularExpression) else { continue }
            let amountStr = String(trimmed[amountMatch])
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let amount = Double(amountStr), amount > 0 && amount < 100000 else { continue }

            // Try to find a date
            var dateStr = ""
            if let dateMatch = trimmed.range(of: datePattern, options: .regularExpression) {
                dateStr = String(trimmed[dateMatch])
            }

            // Extract merchant: everything between date and amount
            var merchant = trimmed
            if !dateStr.isEmpty, let dateRange = trimmed.range(of: dateStr) {
                merchant = String(trimmed[dateRange.upperBound...])
            }
            if let amountRange = merchant.range(of: amountStr) {
                merchant = String(merchant[..<amountRange.lowerBound])
            }
            merchant = merchant
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-*#")))

            guard merchant.count > 1 else { continue }

            let isRefund = lower.contains("refund") || lower.contains("credit") || lower.contains("return")

            parsed.append(ParsedTransaction(
                merchant: merchant,
                date: dateStr,
                amount: amount,
                category: isRefund ? "Refund" : "Other",
                isRefund: isRefund,
                statementId: currentStatementId,
                accountLabel: currentAccountLabel,
                parsedDate: Self.resolveDate(dateStr, statementYear: currentStatementYear)
            ))
        }
        return parsed
    }

    // MARK: - Date Resolution

    static func resolveDate(_ dateString: String, statementYear: Int?) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current

        let formats = ["MM/dd/yyyy", "MM/dd/yy", "MM-dd-yyyy", "MM-dd-yy",
                       "MM/dd", "MM-dd", "MMM dd, yyyy", "MMM dd yyyy", "MMM dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if var date = formatter.date(from: trimmed) {
                // If format had no year, attach statement year or current year
                if !format.contains("y") {
                    let year = statementYear ?? calendar.component(.year, from: Date())
                    var comps = calendar.dateComponents([.month, .day], from: date)
                    comps.year = year
                    if let resolved = calendar.date(from: comps) {
                        date = resolved
                    }
                }
                // If resolved date is >2 months in the future, assume previous year
                if date.timeIntervalSinceNow > 60 * 60 * 24 * 62 {
                    if let adjusted = calendar.date(byAdding: .year, value: -1, to: date) {
                        return adjusted
                    }
                }
                return date
            }
        }
        return nil
    }

    // MARK: - Transaction Section Extraction

    /// Finds the transaction/activity section in a credit card statement, skipping headers and legal text
    private func extractTransactionSection(from text: String) -> String {
        let lower = text.lowercased()

        // Common keywords that indicate transaction sections in statements
        let transactionMarkers = [
            "transactions", "transaction detail", "account activity",
            "purchases", "purchase detail", "new charges",
            "payments and credits", "payment activity",
            "activity detail", "account summary",
            "date.*description.*amount", "date.*merchant",
            "posted.*description", "trans date"
        ]

        // Find the earliest occurrence of any transaction marker
        var bestStart = text.count
        for marker in transactionMarkers {
            if let range = lower.range(of: marker) {
                let pos = text.distance(from: text.startIndex, to: range.lowerBound)
                if pos < bestStart {
                    bestStart = pos
                }
            }
        }

        // Also look for dollar amount patterns as a fallback
        if bestStart == text.count {
            // Look for first line with a dollar amount like $12.34 or 12.34
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if line.range(of: #"\$?\d+\.\d{2}"#, options: .regularExpression) != nil &&
                   line.count > 10 && line.count < 200 {
                    // Found a line with an amount - start from a few lines before
                    let startLine = max(0, i - 2)
                    let remaining = lines[startLine...].joined(separator: "\n")
                    let truncated = String(remaining.prefix(4000))
                    print("[FinanceManager] Found dollar amounts starting at line \(i)")
                    return truncated
                }
            }
        }

        // If we found a transaction section, extract from there
        if bestStart < text.count {
            let startIdx = text.index(text.startIndex, offsetBy: max(0, bestStart - 50))
            let section = String(text[startIdx...])
            let truncated = String(section.prefix(4000))
            print("[FinanceManager] Found transaction section at position \(bestStart)")
            return truncated
        }

        // Fallback: take the middle portion (skip first 30%, take next 40%)
        let skipChars = text.count / 3
        let startIdx = text.index(text.startIndex, offsetBy: min(skipChars, text.count))
        let section = String(text[startIdx...])
        let truncated = String(section.prefix(4000))
        print("[FinanceManager] No markers found - using middle portion from char \(skipChars)")
        return truncated
    }

    // MARK: - Transaction Management

    func deleteTransaction(_ transaction: ParsedTransaction) {
        transactions.removeAll { $0.id == transaction.id }
        recalculateSpending()
        saveTransactions()
    }

    func updateTransaction(_ transaction: ParsedTransaction) {
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
            recalculateSpending()
            saveTransactions()
        }
    }

    func addTransaction(merchant: String, date: String, amount: Double, category: String) {
        let transaction = ParsedTransaction(
            merchant: merchant, date: date, amount: amount, category: category
        )
        transactions.append(transaction)
        recalculateSpending()
        saveTransactions()
    }

    func clearAllTransactions() {
        transactions.removeAll()
        categorySpending.removeAll()
        monthlySpending.removeAll()
        statements.removeAll()
        totalSpending = 0
        statementCount = 0
        rawStatementText = ""
        hasProcessedStatement = false
        processingError = nil
        selectedAccount = nil
        UserDefaults.standard.removeObject(forKey: "finance_transactions")
        UserDefaults.standard.removeObject(forKey: "finance_statements")
        print("[FinanceManager] All data cleared")
    }

    // MARK: - Calculations

    func recalculateSpending() {
        let filtered = filteredTransactions
        let purchaseTotal = filtered.filter { !$0.isRefund }.reduce(0) { $0 + $1.amount }
        let refundAmt = filtered.filter { $0.isRefund }.reduce(0) { $0 + $1.amount }
        totalSpending = purchaseTotal - refundAmt

        var categoryTotals: [String: Double] = [:]
        for t in filtered where !t.isRefund {
            categoryTotals[t.category, default: 0] += t.amount
        }

        let sorted = categoryTotals.sorted { $0.value > $1.value }
        categorySpending = sorted.map { cat, amount in
            SpendingCategory(
                category: cat,
                amount: amount,
                percentage: totalSpending > 0 ? amount / totalSpending : 0,
                color: ParsedTransaction(merchant: "", date: "", amount: 0, category: cat).color
            )
        }

        recalculateMonthlySpending()
    }

    private func recalculateMonthlySpending() {
        let calendar = Calendar.current
        let dated = filteredTransactions.filter { $0.parsedDate != nil && !$0.isRefund }

        var monthlyTotals: [DateComponents: Double] = [:]
        for t in dated {
            let comps = calendar.dateComponents([.year, .month], from: t.parsedDate!)
            monthlyTotals[comps, default: 0] += t.amount
        }

        // Subtract refunds per month
        let refunds = filteredTransactions.filter { $0.parsedDate != nil && $0.isRefund }
        for t in refunds {
            let comps = calendar.dateComponents([.year, .month], from: t.parsedDate!)
            monthlyTotals[comps, default: 0] -= t.amount
        }

        monthlySpending = monthlyTotals
            .compactMap { comps, total -> MonthlySpending? in
                guard let date = calendar.date(from: comps) else { return nil }
                return MonthlySpending(month: date, totalSpent: max(0, total))
            }
            .sorted { $0.month < $1.month }
    }

    private func createStatementInfo(transactionCount: Int) {
        let label = currentAccountLabel ?? "Unknown"
        let dates = transactions
            .filter { $0.statementId == currentStatementId }
            .compactMap { $0.parsedDate }
            .sorted()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        var dateRange = ""
        if let first = dates.first, let last = dates.last {
            dateRange = formatter.string(from: first)
            if !Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
                dateRange += " - \(formatter.string(from: last))"
            }
        }

        let info = StatementInfo(
            id: currentStatementId ?? UUID(),
            accountLabel: label,
            uploadDate: Date(),
            transactionCount: transactionCount,
            dateRange: dateRange
        )
        statements.append(info)
    }

    // MARK: - Persistence

    func saveTransactions() {
        if let data = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(data, forKey: "finance_transactions")
        }
        UserDefaults.standard.set(statementCount, forKey: "finance_statement_count")
    }

    func saveStatements() {
        if let data = try? JSONEncoder().encode(statements) {
            UserDefaults.standard.set(data, forKey: "finance_statements")
        }
    }

    func loadTransactions() {
        if let data = UserDefaults.standard.data(forKey: "finance_transactions"),
           let saved = try? JSONDecoder().decode([ParsedTransaction].self, from: data) {
            transactions = saved
            recalculateSpending()
        }
        if let data = UserDefaults.standard.data(forKey: "finance_statements"),
           let saved = try? JSONDecoder().decode([StatementInfo].self, from: data) {
            statements = saved
        }
        statementCount = UserDefaults.standard.integer(forKey: "finance_statement_count")
    }

    // MARK: - Context for LLM

    func financeContextString() -> String {
        let filtered = filteredTransactions
        guard !filtered.isEmpty else {
            return "No financial data loaded. The user hasn't uploaded any statements yet."
        }

        let refunds = filtered.filter { $0.isRefund }
        let accountNote = selectedAccount != nil ? " (account: \(selectedAccount!))" : ""

        var context = "User's financial data\(accountNote) (\(purchases.count) purchases, \(refunds.count) refunds from \(statementCount) statement(s)):\n"
        context += "Net spending: $\(String(format: "%.2f", totalSpending))\n"
        context += "Average per purchase: $\(String(format: "%.2f", averageTransaction))\n"
        if !refunds.isEmpty {
            context += "Total refunds: $\(String(format: "%.2f", refundTotal))\n"
        }

        // Monthly trends
        if monthlySpending.count > 1 {
            context += "\nMonthly spending trend:\n"
            for (i, m) in monthlySpending.enumerated() {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                context += "- \(formatter.string(from: m.month)): $\(String(format: "%.0f", m.totalSpent))"
                if i > 0 {
                    let prev = monthlySpending[i - 1].totalSpent
                    if prev > 0 {
                        let change = ((m.totalSpent - prev) / prev) * 100
                        context += " (\(change > 0 ? "+" : "")\(String(format: "%.0f", change))%)"
                    }
                }
                context += "\n"
            }
        }

        // Accounts
        if availableAccounts.count > 1 {
            context += "\nAccounts: \(availableAccounts.joined(separator: ", "))\n"
        }

        if let largest = largestTransaction {
            context += "\nLargest expense: \(largest.merchant) - $\(String(format: "%.2f", largest.amount)) (\(largest.category))\n"
        }

        context += "\nSpending by category:\n"
        for cat in categorySpending {
            context += "- \(cat.category): $\(String(format: "%.2f", cat.amount)) (\(Int(cat.percentage * 100))%)\n"
        }
        // Include transactions but cap to avoid exceeding context window
        // Summaries above are always included; individual transactions may be truncated
        let maxTransactions = 100
        let txToShow = filtered.count <= maxTransactions ? filtered : Array(filtered.suffix(maxTransactions))

        if filtered.count > maxTransactions {
            context += "\nRecent \(maxTransactions) of \(filtered.count) transactions (oldest omitted):\n"
        } else {
            context += "\nAll transactions:\n"
        }
        for t in txToShow {
            let prefix = t.isRefund ? "[REFUND] " : ""
            let account = t.accountLabel.map { " [\($0)]" } ?? ""
            context += "- \(prefix)\(t.merchant): $\(String(format: "%.2f", t.amount)) (\(t.category), \(t.date))\(account)\n"
        }
        return context
    }
}
