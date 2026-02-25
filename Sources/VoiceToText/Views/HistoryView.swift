import SwiftUI
import AppKit
import AVFoundation

struct HistoryView: View {
    @EnvironmentObject var historyStore: TranscriptionHistoryStore
    @State private var selectedFilter: HistoryFilter = .all
    @State private var playingRecordId: UUID?
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 16)

            privacyBanner
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            filterTabs
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            Divider()

            recordsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("历史记录")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                if !historyStore.records.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            stopAudio()
                            historyStore.clearAll()
                        } label: {
                            Label("清空所有记录", systemImage: "trash")
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

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                    Text("保存历史")
                        .font(.subheadline)
                    Text("您希望在设备上保存口述历史多久？")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { historyStore.retention },
                        set: { historyStore.setRetention($0) }
                    )) {
                        ForEach(HistoryRetention.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                let total = historyStore.records.compactMap(\.totalCost).reduce(0, +)
                if total > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "yensign.circle")
                            .foregroundColor(.secondary)
                        Text("累计花费")
                            .font(.subheadline)
                        Text(formatCost(total))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
        }
    }

    // MARK: - Privacy Banner

    private var privacyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("您的数据已加密保护")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("语音和文字数据使用 AES-256-GCM 加密存储在本地数据库中，仅存储在您的设备上。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 4) {
            ForEach(HistoryFilter.allCases, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedFilter == filter ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Records List

    private var recordsList: some View {
        ScrollView {
            if historyStore.filteredRecords(filter: selectedFilter).isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let groups = historyStore.recordsGroupedByDate(filter: selectedFilter)
                    ForEach(groups, id: \.0) { dateString, records in
                        Section {
                            ForEach(records) { record in
                                recordRow(record)
                                Divider()
                                    .padding(.leading, 80)
                            }
                        } header: {
                            dateSectionHeader(dateString)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无记录")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("按住 Fn 键开始语音输入，转录结果将自动保存在这里")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func dateSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }

    private func recordRow(_ record: TranscriptionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeString(from: record.date))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayText)
                    .font(.body)
                    .lineLimit(3)
                if record.didUseRefinement && record.rawText != record.refinedText {
                    Text("原文: \(record.rawText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                metadataRow(record)
            }

            Spacer()

            HStack(spacing: 8) {
                if record.hasAudio {
                    Button {
                        toggleAudio(for: record)
                    } label: {
                        Image(systemName: playingRecordId == record.id ? "stop.circle.fill" : "play.circle")
                            .foregroundColor(playingRecordId == record.id ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(playingRecordId == record.id ? "停止播放" : "播放录音")
                }

                Button {
                    copyToClipboard(record.displayText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制到剪贴板")

                Button {
                    if playingRecordId == record.id { stopAudio() }
                    historyStore.deleteRecord(record)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Audio Playback

    private func toggleAudio(for record: TranscriptionRecord) {
        if playingRecordId == record.id {
            stopAudio()
            return
        }
        guard let data = record.audioData else { return }
        do {
            let player = try AVAudioPlayer(data: data)
            player.play()
            audioPlayer = player
            playingRecordId = record.id

            let duration = player.duration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
                if playingRecordId == record.id {
                    stopAudio()
                }
            }
        } catch {
            print("[History] Audio playback failed: \(error)")
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordId = nil
    }

    // MARK: - Metadata

    @ViewBuilder
    private func metadataRow(_ record: TranscriptionRecord) -> some View {
        let hasMeta = record.transcriptionMeta != nil || record.refinementMeta != nil
        if hasMeta {
            HStack(spacing: 12) {
                if let stt = record.transcriptionMeta {
                    metadataTag(icon: "waveform", text: "\(stt.model)  \(formatDuration(stt.responseTime))")
                }
                if let llm = record.refinementMeta {
                    let parts = [
                        llm.model,
                        llm.tokenUsage.map { "\($0.totalTokens) tokens" },
                        formatDuration(llm.responseTime)
                    ].compactMap { $0 }
                    metadataTag(icon: "sparkles", text: parts.joined(separator: "  "))
                }
                if let cost = record.totalCost {
                    metadataTag(icon: "yensign.circle", text: formatCost(cost))
                }
            }
            .padding(.top, 2)
        }
    }

    private func metadataTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.8))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        }
        return String(format: "%.1fs", seconds)
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "¥%.4f", cost)
        }
        return String(format: "¥%.2f", cost)
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        DateFormatting.timeString(from: date)
    }

    private func copyToClipboard(_ text: String) {
        ClipboardService.copy(text)
    }
}
