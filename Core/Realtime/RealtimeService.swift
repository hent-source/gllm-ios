import Foundation
import Observation

/// Одно соединение realtime на всё приложение.
///
/// Событий от сервера много видов (сообщения, «печатает», прочтение,
/// присутствие, уведомления, звонки), и разным экранам нужны разные.
/// Вместо того чтобы каждый экран открывал своё соединение — а сервер
/// этого не любит, он держит по одному на пользователя — здесь поток
/// один, а события раздаются через NotificationCenter.
@Observable
@MainActor
final class RealtimeService {

    static let shared = RealtimeService()

    private(set) var isConnected = false
    /// Пользователи, которые сейчас в сети. Обновляется событиями presence.
    private(set) var onlineUsers: Set<Int> = []

    private var stream: EventStream?
    private let decoder = JSONDecoder()

    private init() {}

    /// Запускает поток, если он ещё не запущен.
    func ensureRunning() async {
        guard stream == nil else { return }
        guard SessionStore.shared.isAuthorized else { return }

        let client = APIClient.shared
        let stream = EventStream(baseURL: client.baseURL)
        self.stream = stream

        stream.onConnected = { [weak self] in
            Task { @MainActor in
                self?.isConnected = true
            }
        }

        stream.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }

        stream.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        stream.start()
    }

    func stop() {
        stream?.stop()
        stream = nil
        isConnected = false
        onlineUsers = []
    }

    // MARK: - Разбор событий

    private func handle(_ event: EventStream.Event) {
        switch event.name {

        case RealtimeEvent.hello:
            isConnected = true

        case RealtimeEvent.message:
            // { from: User, message: Message }
            guard let payload = event.decode(MessageEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimIncomingMessage,
                object: IncomingMessagePayload(user: payload.from, message: payload.message)
            )

        case RealtimeEvent.messageSent:
            // Подтверждение своей отправки: { to: Int, message: Message }
            guard let payload = event.decode(SentEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimMessageSent,
                object: SentMessagePayload(peerID: payload.to, message: payload.message)
            )

        case RealtimeEvent.typing:
            guard let payload = event.decode(TypingEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimTyping,
                object: TypingPayload(peerID: payload.from)
            )

        case RealtimeEvent.read:
            guard let payload = event.decode(ReadEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimReadReceipt,
                object: ReadPayload(peerID: payload.by, at: payload.at)
            )

        case RealtimeEvent.messageDeleted:
            guard let payload = event.decode(DeletedEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimMessagesDeleted,
                object: DeletedPayload(peerID: payload.peer, ids: payload.ids)
            )

        case RealtimeEvent.messageEdited:
            guard let payload = event.decode(EditedEvent.self, using: decoder) else { return }
            NotificationCenter.default.post(
                name: .glimMessageEdited,
                object: EditedPayload(messageID: payload.id, text: payload.text, chat: payload.chat)
            )

        case RealtimeEvent.presence:
            guard let payload = event.decode(PresenceEvent.self, using: decoder) else { return }
            if payload.online {
                onlineUsers.insert(payload.id)
            } else {
                onlineUsers.remove(payload.id)
            }
            NotificationCenter.default.post(name: .glimPresenceChanged, object: payload)

        case RealtimeEvent.notification:
            NotificationCenter.default.post(name: .glimNotification, object: event.data)

        case RealtimeEvent.call:
            NotificationCenter.default.post(name: .glimCallSignal, object: event.data)

        case RealtimeEvent.post:
            // Новая запись у того, на кого подписан.
            NotificationCenter.default.post(name: .glimNewPost, object: event.data)

        default:
            break
        }
    }
}

// MARK: - Структуры событий

struct MessageEvent: Decodable {
    let from: User
    let message: Message
}

struct SentEvent: Decodable {
    let to: Int
    let message: Message
}

struct TypingEvent: Decodable {
    let from: Int
}

struct ReadEvent: Decodable {
    let by: Int
    let at: Int
}

struct DeletedEvent: Decodable {
    let peer: Int
    let ids: [Int]
}

struct EditedEvent: Decodable {
    let chat: String
    let id: Int
    let text: String
}

struct PresenceEvent: Decodable {
    let id: Int
    let online: Bool
    let lastSeen: Int?
}

// MARK: - Полезные нагрузки уведомлений

struct IncomingMessagePayload {
    let user: User
    let message: Message
}

struct SentMessagePayload {
    let peerID: Int
    let message: Message
}

struct TypingPayload {
    let peerID: Int
}

struct ReadPayload {
    let peerID: Int
    let at: Int
}

struct DeletedPayload {
    let peerID: Int
    let ids: [Int]
}

struct EditedPayload {
    let messageID: Int
    let text: String
    let chat: String
}

// MARK: - Имена уведомлений

extension Notification.Name {
    static let glimIncomingMessage = Notification.Name("glim.incomingMessage")
    static let glimMessageSent = Notification.Name("glim.messageSent")
    static let glimTyping = Notification.Name("glim.typing")
    static let glimReadReceipt = Notification.Name("glim.readReceipt")
    static let glimMessagesDeleted = Notification.Name("glim.messagesDeleted")
    static let glimMessageEdited = Notification.Name("glim.messageEdited")
    static let glimPresenceChanged = Notification.Name("glim.presence")
    static let glimNotification = Notification.Name("glim.notification")
    static let glimCallSignal = Notification.Name("glim.callSignal")
    static let glimNewPost = Notification.Name("glim.newPost")
}
