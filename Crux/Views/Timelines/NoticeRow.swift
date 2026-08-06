//
//  NoticeRow.swift
//  Crux
//

import SwiftUI

///some sort of notice in the timeline
struct NoticeRow: View {
    let notice: TimelineModel.Notice
    let timestamp: Date

    @State private var showsDetail = false

    var body: some View {
        Button {
            showsDetail = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: notice.icon)
                Text(notice.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "info.circle")
                    .font(.caption)
                Text(timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert(notice.title, isPresented: $showsDetail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice.detail)
        }
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 2) {
        NoticeRow(notice: .init(icon: "trash", title: "Message deleted",
                                detail: "This message was removed by its sender or a room moderator."),
                 timestamp: Date())
        NoticeRow(notice: .init(icon: "lock.trianglebadge.exclamationmark", title: "Unable to decrypt",
                                detail: "Sent before this device existed — verify this device in Settings to retrieve the keys."),
                 timestamp: Date())
        NoticeRow(notice: .init(icon: "chart.bar", title: "Poll: Where should we hike?",
                                detail: "Polls aren't supported in Crux yet — open this room in another client to vote."),
                 timestamp: Date())
    }
    .padding()
}
#endif
