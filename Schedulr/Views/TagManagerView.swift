import SwiftUI

struct TagManagerView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Bindable private var settings: AppSettings = .shared
    @State private var searchText = ""
    @State private var renamingTag: String?
    @State private var renameText = ""
    @State private var showingMergeSheet = false
    @State private var mergeSourceTag: String?
    @State private var mergeTargetTag: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var allTags: [(tag: String, count: Int)] {
        var tagCounts: [String: Int] = [:]
        for schedule in viewModel.schedules {
            for tag in schedule.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        let sorted = tagCounts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.tag.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()
                    .ignoresSafeArea()

                List {
                    if allTags.isEmpty {
                        ContentUnavailableView {
                            Label("No Tags", systemImage: "tag")
                        } description: {
                            Text("Tags added to schedules will appear here.")
                        }
                    } else {
                        tagCloudSection
                        tagListSection
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Tags")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Tag", isPresented: Binding(
                get: { renamingTag != nil },
                set: { if !$0 { renamingTag = nil } }
            )) {
                TextField("New name", text: $renameText)
                Button("Rename") {
                    if let oldTag = renamingTag {
                        viewModel.renameTag(oldTag, to: renameText)
                        renamingTag = nil
                    }
                }
                Button("Cancel", role: .cancel) { renamingTag = nil }
            }
            .preferredColorScheme(settings.preferredColorScheme)
        }
    }

    private var tagCloudSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(allTags, id: \.tag) { item in
                    tagCloudChip(item.tag, count: item.count)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Tag Cloud")
        }
    }

    private var tagListSection: some View {
        Section {
            ForEach(allTags, id: \.tag) { item in
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(item.tag)
                    Spacer()
                    Text("\(item.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button {
                        renamingTag = item.tag
                        renameText = item.tag
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        viewModel.deleteTag(item.tag)
                    } label: {
                        Label("Delete Tag", systemImage: "trash")
                    }

                    if allTags.count > 1 {
                        Menu("Merge Into...") {
                            ForEach(allTags.filter { $0.tag != item.tag }, id: \.tag) { target in
                                Button(target.tag) {
                                    viewModel.mergeTags(source: item.tag, into: target.tag)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("All Tags (\(allTags.count))")
        }
    }

    private func tagCloudChip(_ tag: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.chipFill(for: colorScheme), in: Capsule())
    }
}
