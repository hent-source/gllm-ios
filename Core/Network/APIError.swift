import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case rateLimited(message: String?)
    case server(status: Int, message: String?)
    case transport(underlying: Error)
    case decoding(underlying: Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес запроса"
        case .unauthorized:
            return "Нужно войти в аккаунт"
        case .notFound:
            return "Не найдено"
        case .rateLimited(let message):
            return message ?? "Слишком много запросов, подождите минуту"
        case .server(_, let message):
            // Сервер Glim присылает готовый текст на русском — показываем его.
            return message ?? "Ошибка сервера"
        case .transport:
            return "Нет связи с сервером"
        case .decoding:
            return "Сервер ответил неожиданно"
        case .unknown:
            return "Неизвестная ошибка"
        }
    }
}
