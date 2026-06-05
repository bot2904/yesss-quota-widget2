import AppKit
import SwiftUI

struct TrayPopoverView: View {
    @ObservedObject var viewModel: TrayViewModel

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let currentLabel = viewModel.snapshot.account.currentLabel, !currentLabel.isEmpty {
                Text(currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.statusText)
                .font(.caption)
                .foregroundColor(viewModel.snapshot.status == .ok ? .secondary : .red)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.snapshot.status != .ok && !viewModel.snapshot.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.snapshot.warnings.prefix(6), id: \.self) { warning in
                        Text(warning)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let updatedAt = SnapshotDateParser.parse(viewModel.snapshot.updatedAt) {
                Text("Updated: \(Self.timestampFormatter.string(from: updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if viewModel.snapshot.quotas.isEmpty {
                Text("No quota entries available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.snapshot.quotas) { quota in
                            QuotaRowView(quota: quota)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }

            Divider()

            HStack {
                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("YESSS Quotas")
                .font(.headline)

            Spacer()

            Button {
                viewModel.refreshNow()
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
    }
}

private struct QuotaRowView: View {
    let quota: TrayQuota

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(quota.remainingDisplay)
                    .font(.caption)
                    .bold()
            }

            if let progress = quota.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            Text("Used: \(quota.usedDisplay) / \(quota.totalDisplay)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let resetDate = quota.resetDate {
                Text("Resets: \(Self.resetFormatter.string(from: resetDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let validDate = quota.validUntilDate {
                Text("Valid until: \(Self.resetFormatter.string(from: validDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
