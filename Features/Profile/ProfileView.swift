import SwiftUI

/// Профиль. Без параметров — свой аккаунт, с id или ником — чужой.
struct ProfileView: View {

    /// id пользователя или @ник. nil — свой профиль.
    var target: String? = nil

    @State private var user: User?
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let session = SessionStore.shared

    /// Свой профиль, если цель не задана или совпадает с текущим пользователем.
    private var isOwn: Bool {
        guard let target else { return true }
        if let me = session.currentUser, "\(me.id)" == target || me.handle == target {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let user {
                    content(for: user)
                } else {
                    ContentUnavailableView {
                        Label("Профиль недоступен", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text(errorMessage ?? "Не удалось загрузить профиль")
                    } actions: {
                        Button("Повторить") {
                            Task { await load() }
                        }
                    }
                }
            }
            .navigationTitle(isOwn ? "Профиль" : (user?.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await load()
            }
        }
    }

    // MARK: - Содержимое

    private func content(for user: User) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(for: user)
                stats(for: user)

                if isOwn {
                    logoutButton
                } else {
                    followButton(for: user)
                }

                Divider()

                postsList
            }
        }
    }

    private func header(for user: User) -> some View {
        VStack(spacing: 10) {
            CachedAvatar(url: user.avatarURL, size: 96)

            HStack(spacing: 5) {
                Text(user.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                if user.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                }
                if user.premium {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            Text("@\(user.handle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !user.status.isEmpty {
                Text(user.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if user.private {
                Label("Закрытый профиль", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if user.isPublic {
                Label("Сообщество", systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
    }

    private func stats(for user: User) -> some View {
        HStack(spacing: 36) {
            stat(value: user.followers, title: "подписчиков")
            stat(value: user.following, title: "подписок")
            stat(value: posts.count, title: "записей")
        }
    }

    private func stat(value: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func followButton(for user: User) -> some View {
        Button {
            Task { await toggleFollow(user) }
        } label: {
            Text(user.isFollowing ? "Вы подписаны" : "Подписаться")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(user.isFollowing ? .bordered : .borderedProminent)
        .padding(.horizontal)
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            Task { await session.signOut() }
        } label: {
            Text("Выйти")
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var postsList: some View {
        if posts.isEmpty {
            Text("Записей пока нет")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    // В профиле реакции пока только отображаются —
                    // полноценные обработчики живут в ленте.
                    PostRowView(
                        post: post,
                        onReact: { _ in },
                        onSave: {},
                        onRepost: {},
                        onVote: { _ in }
                    )
                    .padding(.horizontal, 16)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Загрузка

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded: User

            if let target, !isOwn {
                let response = try await APIClient.shared.send(
                    .user(target),
                    as: UserResponse.self
                )
                loaded = response.user
            } else {
                let response = try await APIClient.shared.send(.me(), as: MeResponse.self)
                loaded = response.user
            }

            user = loaded

            let postsResponse = try await APIClient.shared.send(
                .userPosts(id: loaded.id),
                as: PostsResponse.self
            )
            posts = postsResponse.posts
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить профиль"
        }
    }

    private func toggleFollow(_ user: User) async {
        do {
            let response = try await APIClient.shared.send(
                .follow(id: user.id, on: !user.isFollowing),
                as: UserResponse.self
            )
            // Сервер вернул профиль с актуальными счётчиками.
            self.user = response.user
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

// MARK: - Аватар

struct CachedAvatar: View {

    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderShape
                }
            } else {
                placeholderShape
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderShape: some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            }
    }
}
