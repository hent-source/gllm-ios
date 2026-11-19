import Foundation

/// Публикация. Соответствует mapPosts() из src/social.js.
struct Post: Decodable, Identifiable, Hashable {
    let id: Int
    let user: User
    let kind: PostKind
    let text: String

    /// Фон для kind == .card — две пары hex-цветов.
    let bg: [String]?
    /// Имя файла медиа, полный адрес собирается через mediaURL(_:).
    let media: String?
    /// Карусель: все изображения поста, включая главное.
    let images: [String]

    let poll: Poll?

    /// Реакции: эмодзи → количество.
    let reactions: [String: Int]
    /// Моя реакция, если есть.
    let my: String?

    let comments: [Comment]

    let saved: Bool
    let edited: Bool
    let boosted: Bool
    let reposts: Int
    let reposted: Bool
    let stars: Int

    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id, user, kind, text, bg, media, images, poll
        case reactions, my, comments, saved, edited, boosted
        case reposts, reposted, stars, createdAt
    }

    /// Сумма всех реакций — то, что показываем как «лайки».
    var totalReactions: Int {
        reactions.values.reduce(0, +)
    }

    /// Отмечен ли пост моей реакцией по умолчанию.
    var isLiked: Bool { my != nil }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

enum PostKind: String, Decodable {
    case plain
    case card
    case photo
    case poll

    /// Неизвестный тип не должен ронять декодирование всего ответа.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PostKind(rawValue: raw) ?? .plain
    }
}

struct Poll: Decodable, Hashable {
    let options: [PollOption]
    /// Индекс моего варианта, если голосовал.
    let my: Int?
}

struct PollOption: Decodable, Hashable {
    let t: String   // текст варианта
    let v: Int      // количество голосов
}

struct Comment: Decodable, Identifiable, Hashable {
    let id: Int
    let user: User
    let text: String
    let createdAt: Int
    /// 0 — обычный комментарий, иначе id родительского.
    let parent: Int
}

// MARK: - Запросы

struct CreatePostRequest: Encodable {
    var text: String
    var kind: String = "plain"
    /// Для kind == "card": два hex-цвета.
    var bg: [String]? = nil
    /// Для kind == "photo": base64 или отпечаток загруженного файла.
    var image: String? = nil
    /// Для kind == "poll".
    var options: [String]? = nil
    /// Видимость: all, followers, friends, me.
    var vis: String = "all"
}

struct EditPostRequest: Encodable {
    let text: String
}

struct ReactRequest: Encodable {
    let emoji: String
}

struct CommentRequest: Encodable {
    let text: String
    let parent: Int?
}

struct SaveRequest: Encodable {
    let on: Bool
}

struct VoteRequest: Encodable {
    let option: Int
}

struct FollowRequest: Encodable {
    let follow: Bool
}

// MARK: - Обёртки ответов

struct FeedResponse: Decodable {
    let posts: [Post]
    /// true, если сервер отдал рекомендации, а не хронологию.
    let ranked: Bool?
}

struct PostResponse: Decodable {
    let post: Post
}

struct UsersResponse: Decodable {
    let users: [User]
}

struct UserResponse: Decodable {
    let user: User
}

struct PostsResponse: Decodable {
    let posts: [Post]
}

struct MeResponse: Decodable {
    let user: User
}

struct ReactionResponse: Decodable {
    let reactions: [String: Int]
    let my: String?
}

// MARK: - Ссылки на медиа

enum Media {
    /// Адрес сервера для картинок. Должен совпадать с APIClient.baseURL.
    static let baseURL = "https://example.com"

    /// Сервер отдаёт только имя файла — собираем полный адрес сам.
    static func url(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return URL(string: "\(baseURL)/media/\(name)")
    }

    /// Универсальный случай: сервер может вернуть и готовый адрес,
    /// и путь "/media/имя", и просто имя файла.
    static func absoluteURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return URL(string: baseURL + raw)
        }
        return url(raw)
    }
}
