import Foundation

/// Пользователь. Соответствует ответу profile() из src/social.js.
struct User: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let handle: String
    let bio: String

    let avatar: String
    let cover: String
    let frame: String
    let nameColor: String
    let status: String

    let verified: Bool
    let premium: Bool
    let isPublic: Bool       // это паблик, а не человек
    let private: Bool        // закрытый профиль
    let online: Bool

    let followers: Int
    let following: Int

    let isFollowing: Bool
    let followsYou: Bool

    let createdAt: Int
    let lastSeen: Int
    let level: Int?

    // Показывается только при определённых настройках приватности,
    // поэтому может отсутствовать.
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, handle, bio, avatar, cover, frame, nameColor, status
        case verified, premium, isPublic, private, online
        case followers, following, isFollowing, followsYou
        case createdAt, lastSeen, level, phone
    }

    /// Сервер отдаёт либо готовый адрес, либо путь вида "/media/xxx.jpg",
    /// поэтому собираем URL сами, как и для картинок постов.
    var avatarURL: URL? { Media.absoluteURL(avatar) }

    var displayName: String { name }
}

extension User {
    static let placeholder = User(
        id: 0,
        name: "Пользователь",
        handle: "user",
        bio: "",
        avatar: "",
        cover: "",
        frame: "",
        nameColor: "",
        status: "",
        verified: false,
        premium: false,
        isPublic: false,
        private: false,
        online: false,
        followers: 0,
        following: 0,
        isFollowing: false,
        followsYou: false,
        createdAt: 0,
        lastSeen: 0,
        level: nil,
        phone: nil
    )
}
