//
//  NewsView.swift
//  LocalLLM
//
//
//

import SwiftUI

struct NewsView: View {
    @State private var isConnected = false
    
    var body: some View {
        ZStack {
            if isConnected {
                NewsDashboardView(isConnected: $isConnected)
            } else {
                TechBackground()
                    .ignoresSafeArea()
                NewsConnectView(isConnected: $isConnected)
            }
        }
        .navigationTitle("News Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewsConnectView: View {
    @Binding var isConnected: Bool
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
                .frame(height: 40)
            
            // Hero Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.05))
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    .frame(width: 160, height: 160)
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 10)
            }
            
            VStack(spacing: 16) {
                Text("News Intelligence")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Stay informed with AI-curated news summaries, sentiment analysis, and market impact reports.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            Spacer()
                .frame(height: 20)
            
            VStack(spacing: 16) {
                Button {
                    withAnimation(.spring()) {
                        isConnected = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Connect News Feed")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Button {
                    withAnimation(.spring()) {
                        isConnected = true
                    }
                } label: {
                    Text("Check Demo Data")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

struct NewsDashboardView: View {
    @Binding var isConnected: Bool
    @State private var chatQuery = ""
    @State private var navigateToChat = false
    @State private var showingAddStock = false
    
    // Mock Data
    @State private var watchlist = [
        StockItem(symbol: "AAPL", name: "Apple Inc.", price: "182.52", change: "+1.2%", trend: .up),
        StockItem(symbol: "MSFT", name: "Microsoft", price: "402.10", change: "+0.8%", trend: .up),
        StockItem(symbol: "GOOGL", name: "Alphabet", price: "152.30", change: "-0.5%", trend: .down),
        StockItem(symbol: "NVDA", name: "NVIDIA", price: "721.40", change: "+3.5%", trend: .up)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Dashboard Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Daily Briefing")
                                .font(.title2.bold())
                            Text("Updated 5m ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation {
                                isConnected = false
                            }
                        } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Top Stories Carousel
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            NewsCard(title: "AI Regulation Talks", source: "TechCrunch", time: "2h ago", color: .blue)
                            NewsCard(title: "Market Rally Continues", source: "Bloomberg", time: "4h ago", color: .green)
                            NewsCard(title: "New Energy Breakthrough", source: "Science Daily", time: "5h ago", color: .purple)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Market Sentiment
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Market Sentiment")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack(spacing: 20) {
                            SentimentStat(label: "Tech", value: "+2.4%", trend: .up)
                            SentimentStat(label: "Energy", value: "-0.5%", trend: .down)
                            SentimentStat(label: "Crypto", value: "+5.1%", trend: .up)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Watchlist Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Watchlist")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingAddStock = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            ForEach(watchlist) { stock in
                                StockRow(stock: stock)
                                
                                if stock.id != watchlist.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            
            // Fixed Bottom Input
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    TextField("Ask AI Analyst...", text: $chatQuery)
                        .submitLabel(.send)
                        .onSubmit {
                            if !chatQuery.isEmpty {
                                navigateToChat = true
                            }
                        }
                    
                    Button {
                        if !chatQuery.isEmpty {
                            navigateToChat = true
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(chatQuery.isEmpty ? .gray.opacity(0.3) : .orange)
                    }
                    .disabled(chatQuery.isEmpty)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
            }
            .padding()
            .background(Color(uiColor: .systemGroupedBackground).opacity(0.9).ignoresSafeArea(edges: .bottom))
        }
        .navigationDestination(isPresented: $navigateToChat) {
            AnalysisChatView(context: "News", initialQuery: chatQuery)
        }
        .sheet(isPresented: $showingAddStock) {
            AddStockSheet(watchlist: $watchlist)
        }
    }
}

struct StockItem: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let price: String
    let change: String
    let trend: SentimentStat.Trend
}

struct StockRow: View {
    let stock: StockItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol)
                    .font(.headline)
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(stock.price)
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: stock.trend == .up ? "arrow.up.right" : "arrow.down.right")
                    Text(stock.change)
                }
                .font(.caption)
                .foregroundStyle(stock.trend == .up ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((stock.trend == .up ? Color.green : Color.red).opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding()
    }
}

struct AddStockSheet: View {
    @Binding var watchlist: [StockItem]
    @Environment(\.dismiss) var dismiss
    @State private var symbol = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Stock Symbol (e.g. TSLA)", text: $symbol)
                
                Button("Add to Watchlist") {
                    if !symbol.isEmpty {
                        // Mock add
                        let newStock = StockItem(
                            symbol: symbol.uppercased(),
                            name: "New Company",
                            price: "100.00",
                            change: "+0.0%",
                            trend: .neutral
                        )
                        watchlist.append(newStock)
                        dismiss()
                    }
                }
                .disabled(symbol.isEmpty)
            }
            .navigationTitle("Add Stock")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct NewsCard: View {
    let title: String
    let source: String
    let time: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(source.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 200, height: 140)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SentimentStat: View {
    let label: String
    let value: String
    let trend: Trend
    
    enum Trend {
        case up, down, neutral
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(trend == .up ? .green : (trend == .down ? .red : .gray))
            
            Image(systemName: trend == .up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                .font(.caption)
                .foregroundStyle(trend == .up ? .green : (trend == .down ? .red : .gray))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
