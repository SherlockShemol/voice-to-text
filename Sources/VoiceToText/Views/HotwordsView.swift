import SwiftUI

struct HotwordsView: View {
    @EnvironmentObject var hotwordsManager: HotwordsManager
    @State private var newWord: String = ""
    @State private var searchText: String = ""

    private var filteredHotwords: [String] {
        if searchText.isEmpty { return hotwordsManager.hotwords }
        return hotwordsManager.hotwords.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 16)

            addWordSection
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            filterBar
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            Divider()

            wordsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("词典")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Text("\(hotwordsManager.hotwords.count) / \(Limits.maxHotwords)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(6)
            if !hotwordsManager.hotwords.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        hotwordsManager.clearAll()
                    } label: {
                        Label("清空所有热词", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Add Word

    private var addWordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("添加热词", systemImage: "plus.circle")
                .font(.headline)
            Text("添加专有名词、术语或容易识别错误的词汇，提升语音识别准确率（最多 \(Limits.maxHotwords) 个）")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("输入热词后按回车添加", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button("添加") { addWord() }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || hotwordsManager.hotwords.count >= Limits.maxHotwords)
            }
            if hotwordsManager.hotwords.count >= Limits.maxHotwords {
                Text("已达到热词数量上限")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索热词", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Words List

    private var wordsList: some View {
        ScrollView {
            if filteredHotwords.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredHotwords, id: \.self) { word in
                        wordRow(word)
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
    }

    private func wordRow(_ word: String) -> some View {
        HStack {
            Text(word)
                .font(.body)
            Spacer()
            Button {
                hotwordsManager.remove(word)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            if searchText.isEmpty {
                Text("暂无热词")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("添加专有名词或术语，提升语音识别准确率")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("未找到匹配的热词")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Actions

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if hotwordsManager.add(trimmed) {
            newWord = ""
        }
    }
}
