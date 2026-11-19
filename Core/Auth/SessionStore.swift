import Foundation
import Observation

/// Состояние входа в приложении.
///
/// Токенов нет: сервер Glim использует cookie-сессию, её хранит
/// URLSession автоматически. Здесь только то, вошёл пользователь или нет
/// и кто именно — чтобы не дёргать /api/auth/me на каждом экране.
@Observable
@MainActor
final class SessionStore {

    static let shared = SessionStore()

    /// fileprivate, чтобы уведомление об истёкшей сессии могло сбросить
    /// пользователя изнутри того же файла.
    fileprivate(set) var currentUser: User?
    /// Пока идёт первая проверка сессии, показываем заглушку, а не экран входа.
    fileprivate(set) var isRestoring = true

    var isAuthorized: Bool { currentUser != nil }

    private init() {
        // Сессия истекла на любом запросе — выкидываем на экран входа.
        NotificationCenter.default.addObserver(
            forName: .glimUnauthorized,
            object: nil,
            queue: .main
        ) { _ in
            // Уведомление приходит в главной очереди, а класс целиком
            // изолирован на MainActor — Task только чтобы перейти в него.
            Task { @MainActor in
                SessionStore.shared.currentUser = nil
            }
        }
    }

    /// Проверяет, жива ли сохранённая сессия. Вызывается при запуске.
    func restore() async {
        defer { isRestoring = false }
        do {
            let response = try await APIClient.shared.send(.me(), as: MeResponse.self)
            currentUser = response.user
        } catch {
            // Сессии нет или она протухла — это нормально при первом запуске.
            currentUser = nil
        }
    }

    func signIn(as user: User) {
        currentUser = user
    }

    func signOut() async {
        try? await APIClient.shared.send(.logout())
        clearCookies()
        currentUser = nil
    }

    /// Удаляет все куки — используется при выходе.
    private func clearCookies() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }
}
