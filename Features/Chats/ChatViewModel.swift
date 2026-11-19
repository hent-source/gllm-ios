import Foundation
import Observation

/// Переписка с одним человеком.
@Observable
@MainActor
final class ChatViewModel {

    let peerID: Int
    private(set) var peer: User?
    private(set) var messages: [Message] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var isPeerTyping = false
    private(set) var ttlSeconds = 0
    var errorMessage: String?
    var draft = ""

    /// Ответ, который сейчас набирается (на какое сообщение отвечаем).
    var replyTo: Message?

    private var typingResetTask: Task<Void, Never>?
    private var lastTypingSent = Date.distantPast

    init(peerID: Int) {
        self.peerID = peerID
    }

    // MARK: - Загрузка

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(
                .messages(peerID: peerID),
                as: MessagesResponse.self
            )
            peer = response.user
            messages = response.messages
            canLoadMore = response.more
            ttlSeconds = response.ttl ?? 0
            errorMessage = nil

            // Сервер отдаёт последние 100, в порядке возрастания id.
            try? await APIClient.shared.send(.markChatRead(peerID: peerID))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить переписку"
        }
    }

    /// Подгрузка истории вверх.
    func loadMore() async {
        guard canLoadMore, !isLoadingMore, let oldest = messages.first?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await APIClient.shared.send(
                .messages(peerID: peerID, before: oldest),
                as: MessagesResponse.self
            )
            // Старые сообщения встают в начало списка.
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: response.messages.filter { !known.contains($0.id) }, at: 0)
            canLoadMore = response.more
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    // MARK: - Отправка

    func send(text: String, kind: String = "text", attachment: AttachmentPayload? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != "text" || !trimmed.isEmpty else { return }

        var request = SendMessageRequest(kind: kind, text: trimmed, data: attachment)

        if let reply = replyTo {
            request.reply = ReplyPayload(
                id: reply.id,
                t: reply.text.isEmpty ? reply.kind.preview : String(reply.text.prefix(120)),
                me: reply.me,
                from: nil
            )
        }

        let pendingReply = replyTo
        replyTo = nil

        do {
            let response = try await APIClient.shared.send(
                .sendMessage(peerID: peerID, request),
                as: MessageResponse.self
            )
            messages.append(response.message)
            // Дублировать своё же сообщение из потока событий не нужно —
            // сервер присылает message-sent только нам, и мы его отфильтруем.
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Сообщение не отправилось"
            replyTo = pendingReply
        }
    }

    func delete(message: Message) async {
        do {
            try await APIClient.shared.send(.deleteMessage(peerID: peerID, messageID: message.id))
            messages.removeAll { $0.id == message.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    func edit(message: Message, text: String) async {
        do {
            try await APIClient.shared.send(
                .editMessage(peerID: peerID, messageID: message.id, text: text)
            )
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = messages[index].withText(text, edited: true)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    /// Сообщить серверу, что печатаешь. Не чаще раза в 3 секунды,
    /// чтобы не заваливать сервер на каждую букву.
    func notifyTyping() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingSent) > 3 else { return }
        lastTypingSent = now

        Task {
            try? await APIClient.shared.send(.sendTyping(to: peerID))
        }
    }

    // MARK: - Realtime

    /// Новое сообщение от собеседника.
    func receive(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        isPeerTyping = false

        Task {
            try? await APIClient.shared.send(.markChatRead(peerID: peerID))
        }
    }

    /// Собеседник печатает — показываем индикатор и гасим его через 4 секунды.
    func peerIsTyping() {
        isPeerTyping = true
        typingResetTask?.cancel()
        typingResetTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            isPeerTyping = false
        }
    }

    /// Собеседник прочитал переписку.
    func markRead() {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        messages = messages.map { $0.me && $0.readAt == nil ? $0.withReadAt(now) : $0 }
    }

    func applyDelete(ids: [Int]) {
        messages.removeAll { ids.contains($0.id) }
    }

    func applyEdit(id: Int, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = messages[index].withText(text, edited: true)
    }

    func setTTL(_ seconds: Int) async {
        do {
            try await APIClient.shared.send(.setChatTTL(peerID: peerID, seconds: seconds))
            ttlSeconds = seconds
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
