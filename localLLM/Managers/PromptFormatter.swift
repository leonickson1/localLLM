//
//  PromptFormatter.swift
//  LocalLLM
//
//  Single source of truth for all prompt formatting and system prompts.
//

import Foundation

struct MessageTurn {
    let role: String   // "system", "user", "assistant"
    let content: String
}

// MARK: - Centralized System Prompts

enum SystemPrompt {
    case chat
    case promptLab(PromptTemplate)
    case vision
    case audioSummary
    case healthCoach(healthContext: String)
    case financeAdvisor(financeContext: String)
    case financeParser

    var text: String {
        switch self {
        case .chat:
            return "You are a helpful AI assistant running locally on the user's device. Be concise, accurate, and helpful. All processing happens on-device for privacy."

        case .promptLab(let template):
            switch template {
            case .summarize:
                return "You are a summarization assistant. Summarize the following text concisely, capturing the key points. Output only the summary."
            case .rewrite:
                return "You are a writing assistant. Rewrite the following text to be clearer, more professional, and well-structured. Output only the rewritten text."
            case .generateCode:
                return "You are a coding assistant. Generate clean, well-commented code based on the following description. Include brief explanations."
            case .translate:
                return "You are a translation assistant. Translate the following text to English. If it's already in English, translate it to Spanish. Output only the translation."
            case .custom:
                return "You are a helpful AI assistant."
            }

        case .vision:
            return """
            You are a vision assistant. The user uploaded an image and you have been given extracted text (OCR) and basic image analysis results. \
            Use this information to answer the user's question as helpfully as possible. \
            If the information is insufficient, explain what you can observe and what additional context would help.
            """

        case .audioSummary:
            return "You are a helpful assistant. Summarize and clean up the following audio transcription. Fix grammar issues and organize the content clearly."

        case .healthCoach(let context):
            return """
            You are a health coach AI assistant running locally on the user's device. Analyze their health data and provide actionable, \
            personalized insights based on widely-published public health guidelines.

            CITATION REQUIREMENT (MANDATORY):
            When you mention any health target, range, or recommendation (e.g. heart rate, steps, sleep duration, exercise minutes), \
            you MUST cite the source. Use these sources:
            - CDC Physical Activity Guidelines: https://www.cdc.gov/physicalactivity/basics/adults/index.htm
            - WHO Physical Activity Recommendations: https://www.who.int/news-room/fact-sheets/detail/physical-activity
            - CDC Sleep Recommendations: https://www.cdc.gov/sleep/about_sleep/how_much_sleep.html
            - AHA Target Heart Rate: https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates
            - Apple Health & Activity research: https://www.apple.com/healthcare/

            Format citations inline like: "(per CDC, https://www.cdc.gov/physicalactivity/basics/adults/index.htm)" or as a "Sources:" \
            list at the end of your response. ALWAYS include at least one source URL when referencing health norms or ranges.

            Do not provide medical diagnoses or specific medical advice. End every response with a brief reminder to consult a \
            healthcare provider for personalized medical guidance.

            \(context)
            """

        case .financeAdvisor(let context):
            return """
            You are a personal finance AI assistant running locally on the user's device. Analyze their spending data and provide \
            helpful, practical insights. Be specific with numbers. Do not provide investment advice or specific financial advice. \
            The user may have uploaded multiple statements - the data below includes all of them combined. \
            Category breakdowns and monthly trends reflect the full dataset even if individual transactions are truncated.

            CITATION REQUIREMENT:
            When you reference budgeting principles, savings rules, or financial guidelines (e.g. 50/30/20 rule, emergency fund recommendations), \
            cite a public source. Use these:
            - Consumer Financial Protection Bureau: https://www.consumerfinance.gov/
            - FTC Consumer Advice on budgeting: https://consumer.ftc.gov/articles/making-budget
            - MyMoney.gov (federal resource): https://www.mymoney.gov/

            End every response reminding the user to consult a qualified financial advisor for financial decisions.

            \(context)
            """

        case .financeParser:
            return """
            You are a data extraction tool. Read the credit card statement text the user provides. \
            Extract ONLY transactions that actually appear in the text. \
            NEVER invent, guess, or make up transactions. If a merchant name is not in the text, do not include it.

            If you see a statement period, year, or account number in the text, output this as the FIRST line:
            STATEMENT|last4digits|year
            Example: STATEMENT|4521|2025

            Then output transactions, one per line:
            MERCHANT|DATE|AMOUNT|CATEGORY

            Rules:
            - MERCHANT = exact name from the statement
            - DATE = exact date from the statement. Include the year if visible (e.g. 04/15/2025).
            - AMOUNT = number only, no dollar sign. Use NEGATIVE for refunds/credits/returns.
            - CATEGORY = Dining, Groceries, Transport, Subscription, Shopping, Utilities, Entertainment, Health, Services, Refund, or Other
            - For refunds, returns, or credits: use negative amount AND set category to "Refund"
            - SKIP these entirely (do NOT output them): payments to card (e.g. "PAYMENT THANK YOU", "ONLINE PAYMENT", "AUTOPAY"), \
            balance transfers, fees, interest charges, finance charges, late fees, minimum payment lines, \
            previous balance, new balance, credit limit lines
            - Only extract actual purchases and refunds/credits from merchants
            - Output ONLY the lines, nothing else - no headers, no explanations
            """
        }
    }
}

// MARK: - Prompt Formatter

struct PromptFormatter {

    /// Default context in characters (rough: ~3 chars per token for English)
    static let defaultMaxContextChars = 6000

    /// Convert token context window to approximate character limit
    static func charsForTokens(_ tokens: Int) -> Int {
        max(2000, tokens * 3) // ~3 chars per token, minimum 2000
    }

    static func format(
        systemPrompt: String,
        messages: [MessageTurn],
        template: ChatTemplate,
        contextTokens: Int = 0
    ) -> String {
        let maxChars = contextTokens > 0 ? charsForTokens(contextTokens) : defaultMaxContextChars

        var allMessages = [MessageTurn]()
        if !systemPrompt.isEmpty {
            allMessages.append(MessageTurn(role: "system", content: systemPrompt))
        }
        allMessages.append(contentsOf: messages)

        allMessages = trimToFit(messages: allMessages, maxChars: maxChars)

        switch template {
        case .chatml, .qwen2:
            return formatChatML(allMessages)
        case .llama3:
            return formatLlama3(allMessages)
        case .phi3:
            return formatPhi3(allMessages)
        case .gemma:
            return formatGemma(systemPrompt: systemPrompt, messages: messages)
        }
    }

    /// Convenience: format using a SystemPrompt enum
    static func format(
        systemPrompt: SystemPrompt,
        messages: [MessageTurn],
        template: ChatTemplate,
        contextTokens: Int = 0
    ) -> String {
        format(systemPrompt: systemPrompt.text, messages: messages, template: template, contextTokens: contextTokens)
    }

    // MARK: - Context Window Management

    /// Trims older messages to fit within the context window, keeping system prompt and most recent messages
    private static func trimToFit(messages: [MessageTurn], maxChars: Int) -> [MessageTurn] {
        let totalChars = messages.reduce(0) { $0 + $1.content.count + $1.role.count + 20 } // 20 for template overhead
        guard totalChars > maxChars else { return messages }

        // Always keep system prompt (index 0) and at least the last user message
        guard messages.count > 2 else { return messages }

        var result = [MessageTurn]()

        // Keep system prompt
        if messages.first?.role == "system" {
            result.append(messages[0])
        }

        // Add messages from the end until we approach the limit
        var remaining = maxChars - (result.first?.content.count ?? 0) - 100
        var recentMessages = [MessageTurn]()

        for msg in messages.reversed() {
            if msg.role == "system" { continue }
            let msgSize = msg.content.count + msg.role.count + 20
            if remaining - msgSize > 0 {
                recentMessages.insert(msg, at: 0)
                remaining -= msgSize
            } else {
                break
            }
        }

        result.append(contentsOf: recentMessages)
        return result
    }

    // MARK: - Template Formatters

    /// ChatML format (SmolLM2, Qwen2.5, many others)
    private static func formatChatML(_ messages: [MessageTurn]) -> String {
        var result = ""
        for msg in messages {
            result += "<|im_start|>\(msg.role)\n\(msg.content)<|im_end|>\n"
        }
        result += "<|im_start|>assistant\n"
        return result
    }

    /// Llama 3 format
    private static func formatLlama3(_ messages: [MessageTurn]) -> String {
        var result = "<|begin_of_text|>"
        for msg in messages {
            result += "<|start_header_id|>\(msg.role)<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
        }
        result += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return result
    }

    /// Phi-3 format
    private static func formatPhi3(_ messages: [MessageTurn]) -> String {
        var result = ""
        for msg in messages {
            result += "<|\(msg.role)|>\n\(msg.content)<|end|>\n"
        }
        result += "<|assistant|>\n"
        return result
    }

    /// Gemma format (no system role - prepend to first user message)
    private static func formatGemma(systemPrompt: String, messages: [MessageTurn]) -> String {
        var result = ""
        var isFirstUser = true

        for msg in messages {
            let role = msg.role == "assistant" ? "model" : msg.role
            if role == "system" { continue }

            var content = msg.content
            if role == "user" && isFirstUser && !systemPrompt.isEmpty {
                content = systemPrompt + "\n\n" + content
                isFirstUser = false
            } else if role == "user" {
                isFirstUser = false
            }

            result += "<start_of_turn>\(role)\n\(content)<end_of_turn>\n"
        }

        result += "<start_of_turn>model\n"
        return result
    }
}
