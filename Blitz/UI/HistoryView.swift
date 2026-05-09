import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: TranscriptHistory
    let onRetry: (HistoryEntry) -> Void

    @State private var busyIDs: Set<UUID> = []
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if history.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var header: some View {
        HStack {
            Text("\(history.entries.count) entr\(history.entries.count == 1 ? "y" : "ies")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                history.clear()
            } label: {
                Text("Clear all")
            }
            .disabled(history.entries.isEmpty)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No transcriptions yet")
                .foregroundStyle(.secondary)
            Text("Hold Right-Option and speak to create your first one.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(history.entries) { entry in
                    row(for: entry)
                    Divider()
                }
            }
        }
    }

    private func row(for entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                modeBadge(entry.mode)
                Text(relativeDate(entry.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if busyIDs.contains(entry.id) {
                    ProgressView().controlSize(.small)
                }
                if entry.errorMessage != nil {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(entry.errorMessage ?? "")
                }
            }

            Text(entry.preview)
                .font(.system(size: 13))
                .foregroundStyle(entry.errorMessage == nil ? .primary : .secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    copy(entry)
                } label: {
                    if copiedID == entry.id {
                        Label("Copied!", systemImage: "checkmark")
                    } else {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .controlSize(.small)
                .disabled(!entry.isSuccessful)

                if entry.canRetry {
                    Button {
                        busyIDs.insert(entry.id)
                        onRetry(entry)
                        // The history will update via @Published; clear busy after a tick.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            busyIDs.remove(entry.id)
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive) {
                    history.remove(id: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func modeBadge(_ mode: Mode) -> some View {
        Text(mode.displayName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(for: mode).opacity(0.2))
            .foregroundStyle(color(for: mode))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func color(for mode: Mode) -> Color {
        switch mode {
        case .exact:   return .blue
        case .written: return .green
        case .rage:    return .orange
        case .emoji:   return .purple
        }
    }

    private func copy(_ entry: HistoryEntry) {
        guard let text = entry.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
