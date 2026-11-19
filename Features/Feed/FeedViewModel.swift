import Foundation
import Observation

/// Целиком на главном акторе: все методы меняют состояние экрана,
/// а вызываются они из Task, поэтому изоляция задана на классе,
/// а не на каждом методе по отдельности.
@Observable
@MainActor
final class FeedViewModel {

    var tab: FeedTab? = nil {
        didSet {
            guard oldValue != tab else { return }
            posts = []
            cursor = nil
            Task { await load(reset: true) }
        }
    }

    private(set) var posts: [Post] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var canLoadMore = true
    private(set) var isRanked = false
    var errorMessage: String?

    /// Курсор пагинации — id последнего поста. Сервер отдаёт по 40 за раз.
    private var cursor: Int?

    func load(reset: Bool = false) async {
        guard !isLoading else { return }

        if reset {
            cursor = nil
            canLoadMore = true
        }
        // Рекомендации сервер отдаёт сразу списком, без пагинации.
        guard canLoadMore else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(
                .feed(tab: tab, before: cursor),
                as: FeedResponse.self
            )

            if reset {
                posts = response.posts
            } else {
                // Подстраховка от дублей, если сервер отдал пересечение.
                let known = Set(posts.map(\.id))
                posts.append(contentsOf: response.posts.filter { !known.contains($0.id) })
            }

            cursor = response.posts.last?.id
            isRanked = response.ranked ?? false
            // В рекомендациях курсора нет — подгружать нечего.
            canLoadMore = !isRanked && response.posts.count >= 40
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить ленту"
            canLoadMore = false
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load(reset: true)
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        guard index >= posts.count - 3 else { return }
        await load()
    }

    // MARK: - Реакции

    /// Если моя реакция уже такая же — сервер снимает её (повторная отправка
    /// того же эмодзи работает как переключатель).
    func react(to post: Post, emoji: String) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = posts[index]

        // Оптимистично: сервер посчитает заново, но интерфейс не должен ждать.
        var reactions = original.reactions
        let isRemoving = original.my == emoji

        if let previous = original.my {
            let count = (reactions[previous] ?? 1) - 1
            if count <= 0 { reactions.removeValue(forKey: previous) } else { reactions[previous] = count }
        }
        if !isRemoving {
            reactions[emoji, default: 0] += 1
        }

        posts[index] = original.updating(
            reactions: reactions,
            my: isRemoving ? nil : emoji,
            clearsReaction: isRemoving
        )

        do {
            try await APIClient.shared.send(.react(postID: post.id, emoji: emoji))
        } catch {
            posts[index] = original   // не получилось — откатываем
        }
    }

    func toggleSave(on post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = posts[index]
        posts[index] = original.updating(saved: !original.saved)

        do {
            try await APIClient.shared.send(.savePost(id: post.id, on: !original.saved))
        } catch {
            posts[index] = original
        }
    }

    func toggleRepost(on post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = posts[index]
        posts[index] = original.updating(
            reposted: !original.reposted,
            reposts: original.reposted ? original.reposts - 1 : original.reposts + 1
        )

        do {
            try await APIClient.shared.send(.repost(id: post.id, on: !original.reposted))
        } catch {
            posts[index] = original
        }
    }

    func vote(on post: Post, option: Int) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        guard posts[index].poll?.my == nil else { return }   // голос уже отдан

        do {
            try await APIClient.shared.send(.vote(postID: post.id, option: option))
            // Опрос пересчитывается на сервере — просто перечитываем пост.
            let response = try await APIClient.shared.send(
                .post(id: post.id),
                as: PostResponse.self
            )
            if let current = posts.firstIndex(where: { $0.id == post.id }) {
                posts[current] = response.post
            }
        } catch {
            // опросы не критичны — молча оставляем как есть
        }
    }

    /// Добавляет пост, созданный пользователем, в начало ленты.
    func prepend(_ post: Post) {
        posts.insert(post, at: 0)
    }
}

// MARK: - Копирование с изменениями

extension Post {
    /// Post — структура только для чтения, поэтому изменения делаем копией.
    ///
    /// `my` меняется чаще всего на nil (снятие реакции), а обычный
    /// опционал «не передан» и «передан nil» не различает, поэтому
    /// состояние реакции задаётся отдельным флагом.
    func updating(
        reactions: [String: Int]? = nil,
        my: String? = nil,
        clearsReaction: Bool = false,
        saved: Bool? = nil,
        reposted: Bool? = nil,
        reposts: Int? = nil
    ) -> Post {
        Post(
            id: id,
            user: user,
            kind: kind,
            text: text,
            bg: bg,
            media: media,
            images: images,
            poll: poll,
            reactions: reactions ?? self.reactions,
            my: clearsReaction ? nil : (my ?? self.my),
            comments: comments,
            saved: saved ?? self.saved,
            edited: edited,
            boosted: boosted,
            reposts: reposts ?? self.reposts,
            reposted: reposted ?? self.reposted,
            stars: stars,
            createdAt: createdAt
        )
    }
}
