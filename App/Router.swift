import Foundation
import Observation

/// Навигация между вкладками.
///
/// Из списка чатов нужно открыть переписку, из ленты — профиль автора,
/// из поиска — чат с найденным человеком. Вкладки в SwiftUI живут
/// раздельно, поэтому переходы между ними идут через этот объект:
/// экран меняет выбранную вкладку и кладёт задачу в `pending`.
@Observable
@MainActor
final class Router {

    enum Tab: Hashable {
        case feed
        case chats
        case profile
    }

    /// Equatable нужен для onChange(of:) и navigationDestination(item:).
    enum Destination: Hashable {
        case chat(peerID: Int)
        case profile(userID: Int)
    }

    /// Выбранная вкладка как отдельное значение: Publisher и onChange
    /// сравнивают именно её, а не весь роутер.
    var currentTab: Tab { selectedTab }

    var selectedTab: Tab = .feed

    /// Что открыть после переключения вкладки. Экран забирает задачу
    /// и очищает поле, чтобы переход не повторился.
    private(set) var pending: Destination?
    private var pendingTab: Tab?

    func open(chat peerID: Int) {
        pending = .chat(peerID: peerID)
        pendingTab = .chats
        selectedTab = .chats
    }

    func open(profile userID: Int) {
        pending = .profile(userID: userID)
        pendingTab = .feed
        // Профиль показывается из ленты как push, поэтому вкладку не меняем.
    }

    /// Забрать отложенный переход, если он предназначен этой вкладке.
    func takePending(for tab: Tab) -> Destination? {
        guard pendingTab == tab, let pending else { return nil }
        self.pending = nil
        pendingTab = nil
        return pending
    }
}

// MARK: - Доступ к роутеру

/// @Entry появился только в iOS 18, поэтому ключ объявлен вручную,
/// чтобы проект собирался с iOS 17.
private struct RouterKey: EnvironmentKey {
    @MainActor static let defaultValue = Router()
}

extension EnvironmentValues {
    var glimRouter: Router {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
