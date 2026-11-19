import Foundation

// MARK: - Запросы

struct AuthStartRequest: Encodable {
    let channel: String   // "email" или "sms"
    let to: String
}

struct AuthVerifyRequest: Encodable {
    let channel: String
    let to: String
    let code: String
}

struct AuthSignupRequest: Encodable {
    let ticket: String
    let name: String
    let handle: String
    let bio: String
    let password: String?
}

struct AuthPasswordRequest: Encodable {
    let ticket: String
    let password: String
}

struct AuthTOTPRequest: Encodable {
    let ticket: String
    let code: String
}

// MARK: - Ответы

/// Ответ /api/auth/start.
struct AuthStartResponse: Decodable {
    let ok: Bool
    let channel: String
    let to: String
    let masked: String
}

/// Шаг, который сервер просит выполнить дальше.
enum AuthStep: String, Decodable {
    case profile
    case password
    case totp
    case done
}

/// Ответ /api/auth/verify и последующих шагов.
/// Сервер всегда отдаёт поле next, дальше — поля по ситуации.
struct AuthStepResponse: Decodable {
    let next: AuthStep
    let ticket: String?
    let hint: String?        // подсказка к паролю
    let canReset: Bool?
    let backup: Bool?        // есть ли резервные коды
    let isNew: Bool?
    let user: User?
}
