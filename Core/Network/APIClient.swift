import Foundation

/// Клиент API Glim.
///
/// Особенности сервера, учтённые здесь:
/// — авторизация на cookie-сессии (blik_sid), а не на Bearer-токене;
/// — все ответы — «сырой» JSON без обёртки { data, error };
/// — ошибки приходят как { error, message } с HTTP-статусом;
/// — пагинация курсором `before` по id поста;
/// — все поля camelCase, конвертация ключей не нужна.
///
/// Куку хранит URLSessionConfiguration.httpCookieStorage, поэтому отдельное
/// хранилище токенов не нужно — главное не терять cookies между запусками.
final class APIClient {

    static let shared = APIClient()

    // TODO: заменить на адрес своего сервера.
    // Локально: http://localhost:3000
    // На Aeza:  http://79.137.206.57:порт (или домен, если есть)
    let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = URL(string: "https://example.com")!) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        // Куки должны переживать перезапуск приложения.
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Запросы

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await perform(endpoint)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    /// Для запросов, ответ которых не важен.
    func send(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: - Ядро

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let request = try buildRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            NotificationCenter.default.post(name: .glimUnauthorized, object: nil)
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited(message: Self.message(from: data))
        default:
            throw APIError.server(status: http.statusCode, message: Self.message(from: data))
        }
    }

    private func buildRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        components.path = endpoint.path
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Заголовки эндпоинта — например, для загрузки файлов.
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let raw = endpoint.rawBody {
            // Сырое тело: так шлётся загрузка файлов, заголовки заданы выше.
            request.httpBody = raw
        } else if let body = endpoint.body {
            // Обычный JSON. Сервер отвергает не-JSON тело
            // (защита от подделки межсайтовых запросов).
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    /// Достаёт читаемый текст ошибки из ответа сервера.
    private static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Сервер шлёт { error: 'код', message: 'текст для человека' }
        return object["message"] as? String ?? object["error"] as? String
    }
}

extension Notification.Name {
    /// Сессия истекла — приложение должно вернуть экран входа.
    static let glimUnauthorized = Notification.Name("glim.unauthorized")
}

// MARK: - Стирание типа Encodable

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
