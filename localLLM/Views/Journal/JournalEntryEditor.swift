//
//  JournalEntryEditor.swift
//  LocalLLM
//
//  Clean focused editor. Body text is the primary surface. Mood / photos / links /
//  tags live in a compact bottom toolbar that does not steal attention.
//

import SwiftUI
import PhotosUI

struct JournalEntryEditor: View {
    @EnvironmentObject var journalManager: JournalManager
    @EnvironmentObject var inferenceManager: InferenceManager
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var openAICompat: OpenAICompatibleService
    @EnvironmentObject var parameterStore: ParameterStore
    @Environment(\.dismiss) var dismiss

    let originalEntry: JournalEntry?
    let initialDate: Date?

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var mood: Mood = .mixed
    @State private var date: Date = Date()
    @State private var tagsString: String = ""
    @State private var imageFilenames: [String] = []
    @State private var linkPreviews: [LinkPreview] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPreviews = false
    @State private var aiPrompt: String?
    @State private var isLoadingPrompt = false
    @State private var showDatePicker = false
    @State private var showMoodPicker = false
    @State private var showDeleteConfirm = false
    @State private var showTagsEditor = false
    @State private var floatingHint: String? = nil
    @State private var floatingHintTask: Task<Void, Never>?
    @State private var shouldDiscard = false
    @FocusState private var bodyFocused: Bool

    init(entry: JournalEntry?, initialDate: Date? = nil) {
        self.originalEntry = entry
        self.initialDate = initialDate
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                editorScroll
                bottomToolbar
            }
            .navigationTitle(originalEntry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Delete this entry?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let entry = originalEntry {
                        shouldDiscard = true
                        journalManager.delete(entry)
                        dismiss()
                    }
                }
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(isPresented: $showTagsEditor) {
                TagsEditorSheet(tagsString: $tagsString)
                    .presentationDetents([.height(280)])
            }
            .onChange(of: photoPickerItems) { _, newItems in
                Task { await loadPickedPhotos(newItems) }
            }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
        }
    }

    // MARK: - Top-level layout pieces

    private var editorScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topPillsRow
                if showMoodPicker { moodPickerInline }
                if showDatePicker { datePickerInline }
                titleField
                if let prompt = aiPrompt { aiPromptCard(prompt) }
                bodyField
                if !linkPreviews.isEmpty { linkPreviewList }
                if isLoadingPreviews { loadingPreviewsRow }
                if !imageFilenames.isEmpty { imagesGallery }
                if !displayedTags.isEmpty { tagChipsRow }
                Spacer().frame(height: 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if hasContent {
                    Button(role: .destructive) {
                        shouldDiscard = true
                        dismiss()
                    } label: {
                        Label("Discard changes", systemImage: "trash")
                    }
                }
                if originalEntry != nil {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
                dismiss() // auto-save fires in onDisappear
            }
            .fontWeight(.semibold)
        }
    }

    // MARK: - Pieces

    private var topPillsRow: some View {
        HStack(spacing: 10) {
            moodPill
            datePill
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var moodPill: some View {
        Button { showMoodPicker.toggle() } label: {
            HStack(spacing: 6) {
                Text(mood.emoji).font(.system(size: 18))
                Text(mood.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var datePill: some View {
        Button { showDatePicker.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var moodPickerInline: some View {
        HStack(spacing: 8) {
            ForEach(Mood.allCases) { m in
                MoodPickerCell(mood: m, isSelected: mood == m) {
                    mood = m
                    withAnimation { showMoodPicker = false }
                }
            }
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var datePickerInline: some View {
        DatePicker("", selection: $date)
            .datePickerStyle(.graphical)
            .padding(.horizontal)
    }

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(.system(size: 22, weight: .bold))
            .padding(.horizontal)
            .padding(.top, 6)
    }

    private func aiPromptCard(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.indigo)
            Text(prompt)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.8))
            Spacer()
            Button { aiPrompt = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
    }

    private var bodyField: some View {
        TextField("Write here...", text: $bodyText, axis: .vertical)
            .lineLimit(6...)
            .font(.system(size: 16))
            .lineSpacing(4)
            .padding(.horizontal)
            .focused($bodyFocused)
            .padding(.vertical, 4)
    }

    private var linkPreviewList: some View {
        VStack(spacing: 8) {
            ForEach(linkPreviews) { preview in
                LinkPreviewCard(preview: preview) {
                    linkPreviews.removeAll { $0.id == preview.id }
                }
            }
        }
        .padding(.horizontal)
    }

    private var loadingPreviewsRow: some View {
        // Small inline hint shown while previews are being fetched. The spinner already shows in the
        // floating bar's link icon, but a text confirmation here helps users who do not look there.
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Fetching link previews...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
    }

    /// Gallery layout that matches the Day One / Apple Journal pattern:
    /// 1 image → full-width hero, taller aspect.
    /// 2 images → side-by-side equal squares.
    /// 3+ images → two-column grid with the first image spanning both columns.
    @ViewBuilder
    private var imagesGallery: some View {
        let count = imageFilenames.count
        if count == 1 {
            singleHeroImage(filename: imageFilenames[0])
                .padding(.horizontal)
        } else if count == 2 {
            HStack(spacing: 6) {
                gridImage(filename: imageFilenames[0], height: 180)
                gridImage(filename: imageFilenames[1], height: 180)
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 6) {
                gridImage(filename: imageFilenames[0], height: 220)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Array(imageFilenames.dropFirst().enumerated()), id: \.offset) { _, filename in
                        gridImage(filename: filename, height: 140)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func singleHeroImage(filename: String) -> some View {
        if let img = journalManager.loadImage(filename: filename) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                removeImageButton(filename: filename)
            }
        }
    }

    @ViewBuilder
    private func gridImage(filename: String, height: CGFloat) -> some View {
        if let img = journalManager.loadImage(filename: filename) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                removeImageButton(filename: filename)
            }
        }
    }

    private func removeImageButton(filename: String) -> some View {
        Button {
            imageFilenames.removeAll { $0 == filename }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white, .black.opacity(0.55))
                .padding(8)
        }
    }

    /// Existing tags shown as removable chips inside the scroll, only when there are any.
    private var tagChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayedTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .semibold))
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }

    /// Floating pill-shaped action bar at the bottom. Icon-only, hint text appears above on tap.
    private var bottomToolbar: some View {
        VStack(spacing: 6) {
            if let hint = floatingHint {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            floatingPillBar
        }
        .padding(.bottom, 14)
    }

    private var floatingPillBar: some View {
        HStack(spacing: 2) {
            floatingBarButton(systemName: "sparkles", hint: "Suggest a writing prompt", isActive: isLoadingPrompt) {
                Task { await loadPrompt() }
            }
            floatingBarPhotoPicker
            floatingBarButton(systemName: "link", hint: "Detect links in your text", isActive: isLoadingPreviews) {
                Task { await detectAndFetchLinks() }
            }
            floatingBarButton(systemName: "number", hint: "Add or edit tags") {
                showTagsEditor = true
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(uiColor: .systemBackground).opacity(0.94))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        )
    }

    private func floatingBarButton(systemName: String, hint: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            showHint(hint)
            action()
        } label: {
            Group {
                if isActive {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 44, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var floatingBarPhotoPicker: some View {
        // Use the simpler "photo" SF Symbol (outline-only). The .on.rectangle variant has interior
        // detail that makes it look "filled / activated" next to the other outline icons in the bar.
        // Also drop the .onTapGesture overlay — it was eating taps and confusing the picker state.
        PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 6, matching: .images) {
            Image(systemName: "photo")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .tint(.primary)
    }

    /// Show a transient hint above the floating bar. Fades out after 1.5 seconds.
    private func showHint(_ hint: String) {
        withAnimation(.easeOut(duration: 0.15)) { floatingHint = hint }
        floatingHintTask?.cancel()
        floatingHintTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { floatingHint = nil }
            }
        }
    }

    private var displayedTags: [String] {
        tagsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func removeTag(_ tag: String) {
        tagsString = displayedTags.filter { $0 != tag }.joined(separator: ", ")
    }

    // MARK: - Computed

    private var dateLabel: String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var hasContent: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !imageFilenames.isEmpty
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        if let entry = originalEntry {
            title = entry.title
            bodyText = entry.body
            mood = entry.mood
            date = entry.date
            tagsString = entry.tags.joined(separator: ", ")
            imageFilenames = entry.imageFilenames
            linkPreviews = entry.linkPreviews
        } else if let initialDate = initialDate {
            date = initialDate
        }
        if originalEntry == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                bodyFocused = true
            }
        }
    }

    /// Auto-save when the editor closes, unless the user explicitly discarded.
    /// Matches Day One / Apple Notes behavior — sheet drag-down implicitly saves.
    private func handleDisappear() {
        guard !shouldDiscard, hasContent else { return }
        save()
    }

    // MARK: - Actions

    private func save() {
        let tags = tagsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let entry = JournalEntry(
            id: originalEntry?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: mood,
            date: date,
            tags: tags,
            imageFilenames: imageFilenames,
            linkPreviews: linkPreviews
        )

        if originalEntry == nil {
            journalManager.add(entry)
        } else {
            journalManager.update(entry)
        }
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data),
               let filename = journalManager.saveImage(img) {
                imageFilenames.append(filename)
            }
        }
        photoPickerItems = []
    }

    private func detectAndFetchLinks() async {
        let urls = LinkPreviewService.detectURLs(in: bodyText)
        guard !urls.isEmpty else { return }

        let alreadyHave = Set(linkPreviews.map { $0.urlString })
        let newURLs = urls.filter { !alreadyHave.contains($0.absoluteString) }
        guard !newURLs.isEmpty else { return }

        isLoadingPreviews = true
        for url in newURLs {
            if let preview = await LinkPreviewService.fetchPreview(for: url) {
                linkPreviews.append(preview)
            }
        }
        isLoadingPreviews = false
    }

    private func loadPrompt() async {
        isLoadingPrompt = true
        defer { isLoadingPrompt = false }

        let curatedPrompts = [
            "What's one thing that gave you energy today?",
            "What's something you noticed that you usually wouldn't?",
            "What's been on your mind that you haven't said out loud?",
            "Describe a moment from today in detail.",
            "What are you avoiding right now, and why?",
            "What would you tell yourself from a week ago?",
            "What's something small that went well?",
            "What's something you want to remember about today?"
        ]
        let fallback = curatedPrompts.randomElement() ?? curatedPrompts[0]

        // Personalize against the last 7 days when there's enough history. Falls back to a generic
        // prompt if no entries or no backend.
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = journalManager.entries.filter { $0.date >= weekAgo && $0.id != originalEntry?.id }

        let systemPrompt: String
        let userPrompt: String
        if recent.isEmpty {
            systemPrompt = "You are a thoughtful journaling coach. Give ONE short, evocative writing prompt. One sentence only. No preamble, no quotation marks."
            userPrompt  = "Generate a fresh journaling prompt for today."
        } else {
            let budget = JournalContextBuilder.budget(
                openAICompatActive: openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty,
                ollamaActive: ollamaService.isEnabled && ollamaService.isConnected,
                localContextTokens: inferenceManager.activeContextWindow
            )
            let info = JournalContextBuilder.build(entries: recent, budget: budget)
            systemPrompt = "You are a thoughtful journaling coach. Based on what the user has been writing about, suggest ONE short specific prompt that helps them reflect or go deeper. Reference what they wrote (a recent theme, mood, or thing they mentioned) but keep it to one short sentence. No preamble, no quotation marks."
            userPrompt = info.prompt + "\n\nGenerate the personalized prompt now."
        }

        if openAICompat.isEnabled && openAICompat.isConnected && !openAICompat.selectedModel.isEmpty {
            if let response = await openAICompat.chat(systemPrompt: systemPrompt, userMessage: userPrompt), !response.isEmpty {
                aiPrompt = cleanPrompt(response)
                return
            }
        }
        if ollamaService.isEnabled && ollamaService.isConnected {
            if let response = await ollamaService.chat(systemPrompt: systemPrompt, userMessage: userPrompt), !response.isEmpty {
                aiPrompt = cleanPrompt(response)
                return
            }
        }
        aiPrompt = fallback
    }

    private func cleanPrompt(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip surrounding quotation marks the model might add despite instructions
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("\u{201C}") && s.hasSuffix("\u{201D}")) {
            s.removeFirst(); s.removeLast()
        }
        return s
    }
}

// MARK: - Mood picker cell

private struct MoodPickerCell: View {
    let mood: Mood
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(mood.emoji).font(.system(size: 22))
                Text(mood.label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.indigo.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Link preview card

struct LinkPreviewCard: View {
    let preview: LinkPreview
    let onRemove: () -> Void
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            previewImage
            previewText
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            await loadImage()
        }
    }

    @ViewBuilder
    private var previewImage: some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "link")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let site = preview.siteName {
                Text(site)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(preview.title ?? preview.urlString)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            if let desc = preview.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func loadImage() async {
        guard let imageURLString = preview.imageURL,
              let url = URL(string: imageURLString) else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let img = UIImage(data: data) {
            await MainActor.run { self.image = img }
        }
    }
}

// MARK: - Tags editor sheet

struct TagsEditorSheet: View {
    @Binding var tagsString: String
    @Environment(\.dismiss) var dismiss
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var tags: [String] {
        tagsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add tags to make this entry easier to find later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack {
                    Image(systemName: "number")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Add a tag", text: $input)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($inputFocused)
                        .onSubmit { addCurrent() }
                    if !input.isEmpty {
                        Button("Add") { addCurrent() }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .padding(.horizontal)

                if tags.isEmpty {
                    Text("No tags yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else {
                    ScrollView {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 5) {
                                    Text("#\(tag)")
                                        .font(.system(size: 13, weight: .semibold))
                                    Button {
                                        removeTag(tag)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.indigo.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { inputFocused = true }
        }
    }

    private func addCurrent() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            input = ""
            return
        }
        var newTags = tags
        newTags.append(trimmed)
        tagsString = newTags.joined(separator: ", ")
        input = ""
    }

    private func removeTag(_ tag: String) {
        tagsString = tags.filter { $0 != tag }.joined(separator: ", ")
    }
}

// MARK: - Simple flow layout for tag chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
