import SwiftUI

struct MessageBubble: View {

    let message: Message
    let peer: User?

    var body: some View {
        HStack {
            if message.me { Spacer(minLength: 50) }

            VStack(alignment: message.me ? .trailing : .leading, spacing: 3) {

                if let reply = message.reply {
                    replyPreview(reply)
                }

                if let fwd = message.fwd {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.caption2)
                        Text("Переслано от \(fwd.name)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                bubbleContent
                footer
            }

            if !message.me { Spacer(minLength: 50) }
        }
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.kind {
        case .text:
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isMine: message.me))

        case .photo:
            if let url = message.attachmentURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Color(.secondarySystemBackground)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    default:
                        Color(.secondarySystemBackground)
                            .overlay { ProgressView() }
                    }
                }
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

        case .voice:
            voiceBubble

        case .video:
            videoBubble

        case .sticker, .cstk:
            if let url = message.attachmentURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 120, height: 120)
            } else {
                Text("Стикер").font(.title)
            }

        case .file:
            fileBubble

        case .poll:
            Text("Опрос").font(.subheadline).italic()

        case .geo:
            Label("Геопозиция", systemImage: "map")
                .font(.subheadline)

        case .call:
            Label(message.text.isEmpty ? "Звонок" : message.text, systemImage: "phone")
                .font(.subheadline)

        case .gift:
            Label("Подарок", systemImage: "gift")
                .font(.subheadline)

        case .game:
            Label("Игра", systemImage: "gamecontroller")
                .font(.subheadline)
        }
    }

    // MARK: - Голосовое

    private var voiceBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(message.me ? .white : Color.accentColor)

            // Форма волны из сервера: значения 0-31.
            if let wave = message.data?.wave, !wave.isEmpty {
                HStack(spacing: 1.5) {
                    ForEach(Array(wave.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(message.me ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                            .frame(width: 2, height: max(3, CGFloat(value) * 0.9))
                    }
                }
                .frame(height: 30)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 100, height: 2)
            }

            if let duration = message.data?.dur {
                Text(formatted(duration))
                    .font(.caption)
                    .foregroundStyle(message.me ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .clipShape(BubbleShape(isMine: message.me))
    }

    // MARK: - Видео

    private var videoBubble: some View {
        ZStack {
            if let url = message.attachmentURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.secondarySystemBackground)
                }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
        }
        .frame(width: 200, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Файл

    private var fileBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(message.me ? .white : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.data?.name ?? "Файл")
                    .font(.subheadline)
                    .lineLimit(1)
                if let size = message.data?.size {
                    Text(byteCount(size))
                        .font(.caption2)
                        .foregroundStyle(message.me ? .white.opacity(0.8) : .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .clipShape(BubbleShape(isMine: message.me))
    }

    // MARK: - Ответ

    private func replyPreview(_ reply: ReplyPreview) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.me == true ? "Вы" : (peer?.name ?? ""))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                Text(reply.t)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .padding(6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack(spacing: 4) {
            if let rx = message.rx {
                Text(rx).font(.caption)
            }

            Text(message.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if message.me {
                Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark")
                    .font(.caption2)
                    .foregroundStyle(message.isRead ? Color.accentColor : .secondary)
            }
        }
    }

    // MARK: - Оформление

    private var bubbleBackground: Color {
        message.me ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Форма пузыря: у своего сообщения скошен правый нижний угол,
/// у чужого — левый, чтобы было видно, кто написал.
struct BubbleShape: Shape {

    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tail: CGFloat = 5

        var corners = RectangleCornerRadii(
            topLeading: radius,
            bottomLeading: radius,
            bottomTrailing: radius,
            topTrailing: radius
        )

        if isMine {
            corners = RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: tail,
                topTrailing: radius
            )
        } else {
            corners = RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: tail,
                bottomTrailing: radius,
                topTrailing: radius
            )
        }

        return UnevenRoundedRectangle(cornerRadii: corners).path(in: rect)
    }
}
