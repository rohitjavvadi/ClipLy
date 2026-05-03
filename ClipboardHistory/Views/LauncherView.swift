import AppKit
import SwiftUI

struct LauncherView: View {
    @Bindable var appState: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content
        }
        .frame(width: 760, height: 560)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            searchFocused = true
        }
        .onChange(of: appState.query) {
            appState.refreshRecords()
        }
        .onChange(of: appState.selectedFilter) {
            appState.refreshRecords()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $appState.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .regular))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    FilterButton(filter: filter, selectedFilter: $appState.selectedFilter)
                }
                Spacer()
                Text("\(appState.records.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.records) { record in
                            ClipRowView(
                                record: record,
                                isSelected: record.id == appState.selectedRecordID
                            )
                            .id(record.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedRecordID = record.id
                            }
                            .onTapGesture(count: 2) {
                                appState.selectedRecordID = record.id
                                appState.restoreSelectedAndPaste()
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(width: 430)
                .onChange(of: appState.selectedRecordID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Divider().opacity(0.35)
            PreviewPane(record: appState.selectedRecord())
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

private struct FilterButton: View {
    let filter: HistoryFilter
    @Binding var selectedFilter: HistoryFilter

    var body: some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedFilter == filter ? .primary : .secondary)
        .background(background)
    }

    @ViewBuilder
    private var background: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(selectedFilter == filter ? Color.white.opacity(0.16) : Color.clear)
                .glassEffect(selectedFilter == filter ? .regular.interactive() : .regular, in: .capsule)
        } else {
            Capsule()
                .fill(selectedFilter == filter ? Color.primary.opacity(0.12) : Color.clear)
        }
    }
}

private struct ClipRowView: View {
    let record: ClipboardRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(record.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
            Image(systemName: record.kind.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 42, height: 42)
    }
}

private struct PreviewPane: View {
    let record: ClipboardRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let record {
                HStack(spacing: 10) {
                    Image(systemName: record.kind.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                    Text(record.kind.title)
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                }

                preview(for: record)
                Spacer()
                metadata(for: record)
            } else {
                Spacer()
                ContentUnavailableView("No clips", systemImage: "doc.on.clipboard")
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func preview(for record: ClipboardRecord) -> some View {
        if let thumbnailPath = record.thumbnailPath, let image = NSImage(contentsOfFile: thumbnailPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if !record.filePaths.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(record.filePaths.prefix(5), id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(path)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        } else if let text = record.text {
            ScrollView {
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: 260)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func metadata(for record: ClipboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
            if record.byteCount > 0 {
                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}
