import SwiftUI

struct PostRowView: View {

    let post: Post
    var onReact: (String) -> Void
    var onSave: () -> Void
    var onRepost: () -> Void
    var onVote: (Int) -> Void

    /// Эмодзи, доступные для быстрой реакции.
    private let quickReactions = ["❤️", "🔥", "👍", "😂"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            header

            if post.kind == .card, let bg = post.bg, bg.count == 2 {
                cardBody(colors: bg)
            } else if !post.text.isEmpty {
                Text(post.text)
                    .font(.body)
            }

            if post.kind == .photo {
                photoCarousel
            }

            if let poll = post.poll {
                PollView(poll: poll, onVote: onVote)
            }

            reactionsRow
            footer
        }
        .padding(.vertical, 10)
    }

    // MARK: - Автор

    private var header: some View {
        HStack(spacing: 10) {
            AsyncImageView(url: post.user.avatarURL, size: 40, circular: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(post.user.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if post.user.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if post.user.premium {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                Text("@\(post.user.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if post.boosted {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(post.date, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Пост на фоне

    private func cardBody(colors: [String]) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: colors[0]), Color(hex: colors[1])],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(post.text)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Фото

    private var photoCarousel: some View {
        TabView {
            ForEach(post.images, id: \.self) { name in
                AsyncImageView(url: Media.url(name), height: 300)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: post.images.count > 1 ? .automatic : .never))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Реакции

    private var reactionsRow: some View {
        HStack(spacing: 10) {
            ForEach(quickReactions, id: \.self) { emoji in
                let count = post.reactions[emoji] ?? 0
                let isMine = post.my == emoji

                Button {
                    onReact(emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(emoji)
                            .font(.system(size: 15))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundStyle(isMine ? Color.accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        isMine
                            ? Color.accentColor.opacity(0.15)
                            : Color(.secondarySystemBackground)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack(spacing: 20) {
            Label("\(post.comments.count)", systemImage: "bubble.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onRepost()
            } label: {
                Label("\(post.reposts)", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(post.reposted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                onSave()
            } label: {
                Image(systemName: post.saved ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(post.saved ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            if post.stars > 0 {
                Label("\(post.stars)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            if post.edited {
                Text("изменён")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Опрос

struct PollView: View {

    let poll: Poll
    var onVote: (Int) -> Void

    private var total: Int {
        poll.options.reduce(0) { $0 + $1.v }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                Button {
                    onVote(index)
                } label: {
                    HStack {
                        Text(option.t)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        if hasVoted {
                            Text("\(percent(for: index))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { geometry in
                            if hasVoted {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: geometry.size.width * fraction(for: index))
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if poll.my == index {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(hasVoted)
            }

            HStack {
                Text("\(total) \(plural(total, "голос", "голоса", "голосов"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var hasVoted: Bool { poll.my != nil }

    private func fraction(for index: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(poll.options[index].v) / Double(total)
    }

    private func percent(for index: Int) -> Int {
        Int((fraction(for: index) * 100).rounded())
    }

    private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100, mod10 = n % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        switch mod10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}

// MARK: - Загрузка изображений

struct AsyncImageView: View {

    let url: URL?
    var size: CGFloat? = nil
    var height: CGFloat? = nil
    var circular: Bool = false

    var body: some View {
        content
            .frame(width: size, height: size ?? height)
            .frame(maxWidth: height != nil ? .infinity : nil)
            .clipShape(clipShape)
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    Color(.secondarySystemBackground).overlay { ProgressView() }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color(.secondarySystemBackground)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: (size ?? 40) * 0.45))
                    .foregroundStyle(.secondary)
            }
    }

    private var clipShape: AnyShape {
        circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Цвет из hex

extension Color {
    /// Сервер отдаёт цвета фона в виде "#rrggbb".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
