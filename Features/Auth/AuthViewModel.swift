import Foundation
import Observation

/// Вход в Glim устроен в несколько шагов, и шаги выбирает сервер:
///   почта → код → (профиль для нового аккаунта | пароль | аутентификатор) → готово
///
/// Модель повторяет эту последовательность: экран показывает то поле,
/// которое сервер запросил в поле `next`.
/// Изоляция на классе: все шаги меняют состояние экрана из Task.
@Observable
@MainActor
final class AuthViewModel {

    enum Step {
        case email          // ввод почты
        case code           // ввод кода из письма
        case profile        // регистрация: имя, ник, описание
        case password       // облачный пароль
        case totp           // код из аутентификатора
        case backup         // резервный код
    }

    private(set) var step: Step = .email
    private(set) var isLoading = false
    var errorMessage: String?

    // Ввод
    var email = ""
    var code = ""
    var name = ""
    var handle = ""
    var bio = ""
    var password = ""

    // Подсказки от сервера
    private(set) var maskedDestination = ""
    private(set) var passwordHint = ""
    private(set) var canResetPassword = false
    private(set) var hasBackupCodes = false
    private(set) var isHandleAvailable: Bool?

    /// Тикет — пропуск между шагами. Без него сервер не примет следующий запрос.
    private var ticket = ""

    var canSubmit: Bool {
        guard !isLoading else { return false }
        switch step {
        case .email:
            return email.contains("@") && email.count > 4
        case .code:
            return code.count >= 4
        case .profile:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
                && handle.count >= 3
                && isHandleAvailable != false
        case .password, .totp, .backup:
            return !password.isEmpty
        }
    }

    // MARK: - Шаг 1: отправить код

    func submitEmail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(
                .authStart(email: email.trimmingCharacters(in: .whitespaces)),
                as: AuthStartResponse.self
            )
            maskedDestination = response.masked
            code = ""
            step = .code
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось отправить код"
        }
    }

    // MARK: - Шаг 2: проверить код

    func submitCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(
                .authVerify(email: email.trimmingCharacters(in: .whitespaces), code: code),
                as: AuthStepResponse.self
            )
            ticket = response.ticket ?? ""
            apply(response)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Код не подошёл"
        }
    }

    // MARK: - Шаг 3а: регистрация

    func submitProfile() async -> User? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(
                .authSignup(
                    ticket: ticket,
                    name: name.trimmingCharacters(in: .whitespaces),
                    handle: handle.lowercased(),
                    bio: bio,
                    password: password.isEmpty ? nil : password
                ),
                as: AuthStepResponse.self
            )
            apply(response)
            return response.user
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать аккаунт"
            return nil
        }
    }

    // MARK: - Шаги 3б–3г

    func submitSecret() async -> User? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let endpoint: Endpoint
        switch step {
        case .password: endpoint = .authPassword(ticket: ticket, password: password)
        case .totp:     endpoint = .authTOTP(ticket: ticket, code: password)
        case .backup:   endpoint = .authBackup(ticket: ticket, code: password)
        default:        return nil
        }

        do {
            let response = try await APIClient.shared.send(endpoint, as: AuthStepResponse.self)
            apply(response)
            return response.user
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не подошло"
            password = ""
            return nil
        }
    }

    // MARK: - Проверка ника

    func checkHandle() async {
        let value = handle.lowercased()
        guard value.count >= 3 else {
            isHandleAvailable = nil
            return
        }

        // Небольшая пауза, чтобы не долбить сервер на каждую букву.
        try? await Task.sleep(for: .milliseconds(400))
        guard value == handle.lowercased() else { return }

        do {
            struct HandleResponse: Decodable { let available: Bool }
            let response = try await APIClient.shared.send(
                .checkHandle(value),
                as: HandleResponse.self
            )
            isHandleAvailable = response.available
        } catch {
            isHandleAvailable = nil
        }
    }

    func backToEmail() {
        step = .email
        errorMessage = nil
        code = ""
    }

    // MARK: - Разбор ответа сервера

    private func apply(_ response: AuthStepResponse) {
        passwordHint = response.hint ?? ""
        canResetPassword = response.canReset ?? false
        hasBackupCodes = response.backup ?? false

        switch response.next {
        case .profile:
            step = .profile
        case .password:
            step = .password
            password = ""
        case .totp:
            step = .totp
            password = ""
        case .done:
            break   // экран закроется сам — SessionStore уже знает пользователя
        }
    }
}
