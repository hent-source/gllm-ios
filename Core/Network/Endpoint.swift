import Foundation

/// Описание одного эндпоинта API.
///
/// Пути сверены с blik-server: всё живёт под префиксом /api/,
/// параметры пагинации — курсор `before` (id поста), не page/limit.
struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var query: [String: String] = [:]
    var body: Encodable? = nil
    var requiresAuth: Bool = true

    /// Сырое тело запроса — для загрузки файлов, где JSON не подходит.
    var rawBody: Data? = nil
    /// Дополнительные заголовки.
    var headers: [String: String] = [:]
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Роуты

extension Endpoint {

    // MARK: Вход по коду (основной путь в Glim)

    /// Шаг 1: отправить код на почту.
    static func authStart(email: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/start",
            method: .post,
            body: AuthStartRequest(channel: "email", to: email),
            requiresAuth: false
        )
    }

    /// Шаг 2: проверить код. Ответ подскажет следующий шаг:
    /// profile (новый аккаунт), password, totp или done.
    static func authVerify(email: String, code: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/verify",
            method: .post,
            body: AuthVerifyRequest(channel: "email", to: email, code: code),
            requiresAuth: false
        )
    }

    /// Шаг 3а: завершить регистрацию нового аккаунта.
    static func authSignup(ticket: String, name: String, handle: String, bio: String, password: String?) -> Endpoint {
        Endpoint(
            path: "/api/auth/signup",
            method: .post,
            body: AuthSignupRequest(
                ticket: ticket,
                name: name,
                handle: handle,
                bio: bio,
                password: password
            ),
            requiresAuth: false
        )
    }

    /// Шаг 3б: ввести облачный пароль.
    static func authPassword(ticket: String, password: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/password",
            method: .post,
            body: AuthPasswordRequest(ticket: ticket, password: password),
            requiresAuth: false
        )
    }

    /// Шаг 3в: код из приложения-аутентификатора.
    static func authTOTP(ticket: String, code: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/totp",
            method: .post,
            body: AuthTOTPRequest(ticket: ticket, code: code),
            requiresAuth: false
        )
    }

    /// Шаг 3г: резервный код.
    static func authBackup(ticket: String, code: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/backup",
            method: .post,
            body: AuthTOTPRequest(ticket: ticket, code: code),
            requiresAuth: false
        )
    }

    /// Проверка свободен ли ник.
    static func checkHandle(_ handle: String) -> Endpoint {
        Endpoint(
            path: "/api/auth/handle",
            query: ["h": handle],
            requiresAuth: false
        )
    }

    // MARK: Сессия

    static func me() -> Endpoint {
        Endpoint(path: "/api/auth/me")
    }

    static func logout() -> Endpoint {
        Endpoint(path: "/api/auth/logout", method: .post)
    }

    // MARK: Лента

    /// tab: nil — рекомендации, "following", "latest", "saved".
    static func feed(tab: FeedTab? = nil, before: Int? = nil) -> Endpoint {
        var query: [String: String] = [:]
        if let tab { query["tab"] = tab.rawValue }
        if let before { query["before"] = "\(before)" }
        return Endpoint(path: "/api/feed", query: query)
    }

    static func post(id: Int) -> Endpoint {
        Endpoint(path: "/api/posts/\(id)")
    }

    /// Публикация. kind: plain, card, photo, poll.
    static func createPost(_ request: CreatePostRequest) -> Endpoint {
        Endpoint(path: "/api/posts", method: .post, body: request)
    }

    static func editPost(id: Int, text: String) -> Endpoint {
        Endpoint(path: "/api/posts/\(id)", method: .patch, body: EditPostRequest(text: text))
    }

    static func deletePost(id: Int) -> Endpoint {
        Endpoint(path: "/api/posts/\(id)", method: .delete)
    }

    /// emoji — «❤️», «🔥» и т.п. Повторная отправка того же снимает реакцию.
    static func react(postID: Int, emoji: String) -> Endpoint {
        Endpoint(
            path: "/api/posts/\(postID)/react",
            method: .post,
            body: ReactRequest(emoji: emoji)
        )
    }

    static func comment(postID: Int, text: String, parent: Int? = nil) -> Endpoint {
        Endpoint(
            path: "/api/posts/\(postID)/comments",
            method: .post,
            body: CommentRequest(text: text, parent: parent)
        )
    }

    static func savePost(id: Int, on: Bool) -> Endpoint {
        Endpoint(path: "/api/posts/\(id)/save", method: .post, body: SaveRequest(on: on))
    }

    static func repost(id: Int, on: Bool) -> Endpoint {
        Endpoint(path: "/api/posts/\(id)/repost", method: .post, body: SaveRequest(on: on))
    }

    static func vote(postID: Int, option: Int) -> Endpoint {
        Endpoint(path: "/api/posts/\(postID)/vote", method: .post, body: VoteRequest(option: option))
    }

    // MARK: Люди

    static func users(query: String? = nil) -> Endpoint {
        var q: [String: String] = [:]
        if let query, !query.isEmpty { q["q"] = query }
        return Endpoint(path: "/api/users", query: q)
    }

    /// Можно передать id или @ник.
    static func user(_ idOrHandle: String) -> Endpoint {
        Endpoint(path: "/api/users/\(idOrHandle)")
    }

    static func userPosts(id: Int) -> Endpoint {
        Endpoint(path: "/api/users/\(id)/posts")
    }

    static func follow(id: Int, on: Bool) -> Endpoint {
        Endpoint(path: "/api/users/\(id)/follow", method: .post, body: FollowRequest(follow: on))
    }

    static func following() -> Endpoint {
        Endpoint(path: "/api/me/following")
    }

    // MARK: Чаты

    static func chats() -> Endpoint {
        Endpoint(path: "/api/chats")
    }

    /// before — id сообщения, до которого грузим историю.
    static func messages(peerID: Int, before: Int? = nil) -> Endpoint {
        var query: [String: String] = [:]
        if let before { query["before"] = "\(before)" }
        return Endpoint(path: "/api/chats/\(peerID)/messages", query: query)
    }

    static func sendMessage(peerID: Int, _ request: SendMessageRequest) -> Endpoint {
        Endpoint(path: "/api/chats/\(peerID)/messages", method: .post, body: request)
    }

    static func editMessage(peerID: Int, messageID: Int, text: String) -> Endpoint {
        Endpoint(
            path: "/api/chats/\(peerID)/messages/\(messageID)",
            method: .patch,
            body: EditMessageRequest(text: text)
        )
    }

    static func deleteMessage(peerID: Int, messageID: Int) -> Endpoint {
        Endpoint(path: "/api/chats/\(peerID)/messages/\(messageID)", method: .delete)
    }

    static func markChatRead(peerID: Int) -> Endpoint {
        Endpoint(path: "/api/chats/\(peerID)/read", method: .post)
    }

    /// Срок жизни сообщений: 0 — обычные, иначе секунды.
    static func setChatTTL(peerID: Int, seconds: Int) -> Endpoint {
        Endpoint(path: "/api/chats/\(peerID)/ttl", method: .post, body: TTLRequest(ttl: seconds))
    }

    static func chatMedia(peerID: Int) -> Endpoint {
        Endpoint(path: "/api/chats/\(peerID)/media")
    }

    // MARK: Группы

    static func groups() -> Endpoint {
        Endpoint(path: "/api/groups")
    }

    static func group(id: Int) -> Endpoint {
        Endpoint(path: "/api/groups/\(id)")
    }

    static func groupMessages(groupID: Int, before: Int? = nil) -> Endpoint {
        var query: [String: String] = [:]
        if let before { query["before"] = "\(before)" }
        return Endpoint(path: "/api/groups/\(groupID)/messages", query: query)
    }

    static func sendGroupMessage(groupID: Int, _ request: SendMessageRequest) -> Endpoint {
        Endpoint(path: "/api/groups/\(groupID)/messages", method: .post, body: request)
    }

    static func markGroupRead(groupID: Int) -> Endpoint {
        Endpoint(path: "/api/groups/\(groupID)/read", method: .post)
    }

    /// Сообщить, что печатаешь.
    static func sendTyping(to peerID: Int) -> Endpoint {
        Endpoint(path: "/api/rt/typing", method: .post, body: TypingRequest(to: peerID))
    }

    // MARK: Загрузка файлов

    /// Загрузка вложения. Сервер ждёт сырые байты файла в теле,
    /// имя файла — в заголовке, а не в JSON. В ответ приходит путь
    /// вида /media/xxx.jpg, его и надо класть в сообщение как data.url.
    ///
    /// kind: photo, video, voice или file.
    static func upload(kind: String, fileName: String, data: Data) -> Endpoint {
        Endpoint(
            path: "/api/upload",
            method: .post,
            query: ["kind": kind],
            rawBody: data,
            headers: [
                // Без этого заголовка сервер отвечает «Неверный запрос»:
                // это защита от подделки межсайтовых запросов.
                "x-blik-upload": "1",
                "x-file-name": fileName.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? fileName
            ]
        )
    }

    // MARK: Уведомления

    static func notifications() -> Endpoint {
        Endpoint(path: "/api/notifications")
    }

    static func markNotificationsRead() -> Endpoint {
        Endpoint(path: "/api/notifications/read", method: .post)
    }
}

enum FeedTab: String {
    case following
    case latest
    case saved
}
