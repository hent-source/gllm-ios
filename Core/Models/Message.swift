import Foundation

/// Сообщение. Соответствует mapMsg() из routes/social.js.
struct Message: Decodable, Identifiable, Hashable {
    let id: Int
    /// Моё ли это сообщение.
    let me: Bool
    let kind: MessageKind
    let text: String
    /// Вложение: url, size, mime, name, для голосовых — dur и wave.
    let data: Attachment?
    let reply: ReplyPreview?
    let fwd: ForwardInfo?
    let createdAt: Int
    /// Время прочтения, nil если не прочитано.
    let readAt: Int?
    /// Реакция собеседника, если есть.
    let rx: String?

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }

    var isRead: Bool { readAt != nil }

    var attachmentURL: URL? {
        Media.absoluteURL(data?.url)
    }
}

// MARK: - Копии с изменениями

extension Message {
    /// Message — структура только для чтения, поэтому правки делаем копией.
    func withText(_ text: String, edited: Bool = false) -> Message {
        Message(
            id: id,
            me: me,
            kind: kind,
            text: text,
            data: data,
            reply: reply,
            fwd: fwd,
            createdAt: createdAt,
            readAt: readAt,
            rx: rx
        )
    }

    func withReadAt(_ at: Int) -> Message {
        Message(
            id: id,
            me: me,
            kind: kind,
            text: text,
            data: data,
            reply: reply,
            fwd: fwd,
            createdAt: createdAt,
            readAt: at,
            rx: rx
        )
    }

    func withReaction(_ emoji: String?) -> Message {
        Message(
            id: id,
            me: me,
            kind: kind,
            text: text,
            data: data,
            reply: reply,
            fwd: fwd,
            createdAt: createdAt,
            readAt: readAt,
            rx: emoji
        )
    }
}

/// Типы сообщений, которые принимает сервер.
enum MessageKind: String, Decodable {
    case text
    case sticker
    case cstk       // свой стикер
    case gift
    case call
    case poll
    case geo
    case game
    case voice
    case video
    case photo
    case file

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MessageKind(rawValue: raw) ?? .text
    }

    /// Текстовое описание для превью в списке чатов.
    var preview: String {
        switch self {
        case .text:    return ""
        case .sticker, .cstk: return "Стикер"
        case .gift:    return "Подарок"
        case .call:    return "Звонок"
        case .poll:    return "Опрос"
        case .geo:     return "Геопозиция"
        case .game:    return "Игра"
        case .voice:   return "Голосовое сообщение"
        case .video:   return "Видеосообщение"
        case .photo:   return "Фото"
        case .file:    return "Файл"
        }
    }
}

struct Attachment: Decodable, Hashable {
    let url: String
    let size: Int?
    let mime: String?
    let name: String?
    /// Длительность для голосовых и видео.
    let dur: Int?
    /// Форма волны для голосовых, значения 0-31.
    let wave: [Int]?
}

/// Ответ на сообщение. `q` — цитата, `t` — короткий текст.
struct ReplyPreview: Decodable, Hashable {
    let id: Int?
    let from: Int?
    let me: Bool?
    let t: String
    let q: Int?

    var isQuote: Bool { q == 1 }
}

struct ForwardInfo: Decodable, Hashable {
    let name: String
}

/// Строка списка чатов.
struct ChatSummary: Decodable, Identifiable, Hashable {
    let user: User
    let last: Message?
    let unread: Int

    var id: Int { user.id }
}

// MARK: - Запросы

struct SendMessageRequest: Encodable {
    var kind: String = "text"
    var text: String = ""
    var data: AttachmentPayload? = nil
    var reply: ReplyPayload? = nil
    var fwd: ForwardPayload? = nil
}

struct AttachmentPayload: Encodable {
    let url: String
    var dur: Int? = nil
    var wave: [Int]? = nil
}

struct ReplyPayload: Encodable {
    let id: Int
    let t: String
    var me: Bool? = nil
    var from: Int? = nil
}

struct ForwardPayload: Encodable {
    let name: String
}

struct EditMessageRequest: Encodable {
    let text: String
}

struct TTLRequest: Encodable {
    let ttl: Int
}

struct TypingRequest: Encodable {
    let to: Int
}

// MARK: - Ответы

struct ChatsResponse: Decodable {
    let chats: [ChatSummary]
}

struct MessagesResponse: Decodable {
    let user: User
    let messages: [Message]
    /// true, если сервер отдал полную страницу и есть что подгружать.
    let more: Bool
    /// Срок жизни сообщений в этом чате, 0 — обычные.
    let ttl: Int?
}

struct MessageResponse: Decodable {
    let message: Message
    /// Дошло ли собеседнику сразу, или лежит до его появления в сети.
    let delivered: Bool?
}

struct UploadResponse: Decodable {
    let file: UploadedFile
}

struct UploadedFile: Decodable {
    let id: String
    /// Путь вида /media/xxx.jpg — его и надо класть в data.url сообщения.
    let url: String
    let name: String?
    let size: Int?
    let mime: String?
    let kind: String?
}
