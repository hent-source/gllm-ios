import Foundation
import Observation

/// Список чатов.
@Observable
@MainActor
final class ChatsViewModel {

    private(set) var chats: [ChatSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(.chats(), as: ChatsResponse.self)
            chats = response.chats
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось загрузить чаты"
        }
    }

    /// Пришло новое сообщение — обновляем превью и поднимаем чат наверх.
    func apply(incoming message: Message, from user: User) {
        if let index = chats.firstIndex(where: { $0.user.id == user.id }) {
            let existing = chats[index]
            chats[index] = ChatSummary(
                user: existing.user,
                last: message,
                // Сообщение от собеседника — считаем непрочитанным,
                // пока пользователь не откроет чат.
                unread: message.me ? existing.unread : existing.unread + 1
            )
            let updated = chats.remove(at: index)
            chats.insert(updated, at: 0)
        } else {
            let summary = ChatSummary(user: user, last: message, unread: message.me ? 0 : 1)
            chats.insert(summary, at: 0)
        }
    }

    /// Своё сообщение — просто обновляем превью.
    func apply(outgoing message: Message, to peerID: Int) {
        guard let index = chats.firstIndex(where: { $0.user.id == peerID }) else { return }
        let existing = chats[index]
        chats[index] = ChatSummary(user: existing.user, last: message, unread: existing.unread)
    }

    func clearUnread(peerID: Int) {
        guard let index = chats.firstIndex(where: { $0.user.id == peerID }) else { return }
        let existing = chats[index]
        guard existing.unread > 0 else { return }
        chats[index] = ChatSummary(user: existing.user, last: existing.last, unread: 0)
    }
}
