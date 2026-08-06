//
//  MediaAttachmentView.swift
//  Crux
//

import SwiftUI

struct MediaAttachmentView: View {
    let media: TimelineModel.MediaAttachment
    var maxHeight: CGFloat = 260
    /// whether it allows tapping
    var allowsFullScreen: Bool = true

    @Environment(UserSession.self) private var session: UserSession?
    @State private var image: UIImage?
    @State private var showsFullScreen = false

    var body: some View {
        Group {
            if media.isImage {
                preview
            } else {
                fileRow
            }
        }
        .padding(.horizontal, 12)
    }

    /// Without a full-screen viewer the tap has to pass straight through, or it
    /// swallows whatever the surrounding view wanted it for.
    @ViewBuilder private var preview: some View {
        if allowsFullScreen {
            imageBox
                .contentShape(.rect)
                .onTapGesture { showsFullScreen = true }
                .fullScreenCover(isPresented: $showsFullScreen) {
                    FullScreenMedia(media: media)
                }
        } else {
            imageBox
        }
    }

    private var imageBox: some View {
        // Reserve the final size up front so the row doesn't jump when the image lands.
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxHeight: maxHeight)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary).overlay { ProgressView() }
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: media.id) {
                guard let session else { return }
                image = await MediaLoader.shared.preview(from: media.source,
                                                         uploaderThumbnail: media.thumbnailSource,
                                                         client: session.client)
            }
            .accessibilityLabel(media.caption ?? media.filename)
    }

    private var fileRow: some View {
        // Stickers carry no filename, and nor does a file whose sender omitted one.
        Label(media.filename.isEmpty ? "Attachment" : media.filename, systemImage: symbolName)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    /// Falls back to a 4:3 box when the sender didn't send dimensions.
    private var aspectRatio: CGFloat {
        guard let width = media.width, let height = media.height, width > 0, height > 0 else {
            return 4.0 / 3.0
        }
        return CGFloat(width) / CGFloat(height)
    }

    private var symbolName: String {
        switch media.kind {
        case .video: "play.rectangle"
        case .audio: "waveform"
        case .file, .image: "doc"
        }
    }
}

/// The attachment at full resolution, on black. Tap anywhere to dismiss.
private struct FullScreenMedia: View {
    let media: TimelineModel.MediaAttachment

    @Environment(UserSession.self) private var session: UserSession?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding()
        }
        .contentShape(.rect)
        .onTapGesture { dismiss() }
        .task {
            guard let session else { return }
            image = await MediaLoader.shared.fullImage(from: media.source, client: session.client)
        }
    }
}
