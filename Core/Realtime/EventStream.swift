import Foundation

/// Realtime в Glim — это Server-Sent Events, а не WebSocket.
///
/// Сервер держит поток открытым на `GET /api/events` и присылает строки вида:
///
///     event: message
///     data: {"from":{...},"message":{...}}
///     (пустая строка)
///
/// Плюс периодические комментарии `: ping` каждые 25 секунд, чтобы соединение
/// не разорвал прокси. На них реагировать не нужно — они просто держат канал.
///
/// `URLSession.bytes(for:)` отдаёт тело потоком построчно, поэтому отдельный
/// парсер событий не нужен — читаем строки и собираем события по мере прихода.
final class EventStream {

    /// Событие от сервера.
    struct Event {
        let name: String
        let data: Data

        func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) -> T? {
            try? decoder.decode(type, from: data)
        }
    }

    private let baseURL: URL
    private let session: URLSession

    private var task: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    /// Обработчик событий. Вызывается на главном потоке.
    var onEvent: ((Event) -> Void)?
    /// Соединение установлено и живёт.
    var onConnected: (() -> Void)?
    /// Соединение потеряно, будет переподключение.
    var onDisconnected: (() -> Void)?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    deinit {
        stop()
    }

    // MARK: - Запуск

    func start() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        task?.cancel()
        task = nil
    }

    /// Цикл переподключения. Сервер сам просит подождать 3 секунды
    /// строкой `retry: 3000` в начале потока.
    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await connect()
            } catch {
                if Task.isCancelled { return }
            }

            await MainActor.run { [weak self] in
                self?.onDisconnected?()
            }

            // Пауза перед новой попыткой.
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func connect() async throws {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = "/api/events"

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Без этого URLSession может буферизовать тело и события придут пачкой.
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = .infinity

        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        if http.statusCode == 401 {
            await MainActor.run {
                NotificationCenter.default.post(name: .glimUnauthorized, object: nil)
            }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: nil)
        }

        await MainActor.run { [weak self] in
            self?.onConnected?()
        }

        // Разбор потока: копим строки, пустая строка завершает событие.
        var eventName = "message"
        var dataLines: [String] = []

        for try await line in bytes.lines {
            if Task.isCancelled { return }

            if line.isEmpty {
                // Конец события — отдаём наверх.
                if !dataLines.isEmpty {
                    let payload = dataLines.joined(separator: "\n")
                    if let data = payload.data(using: .utf8) {
                        let event = Event(name: eventName, data: data)
                        await MainActor.run { [weak self] in
                            self?.onEvent?(event)
                        }
                    }
                }
                eventName = "message"
                dataLines = []
                continue
            }

            // Комментарии (": ping") — просто поддержка соединения.
            if line.hasPrefix(":") { continue }

            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
            // Строку `retry:` игнорируем — переподключение у нас своё.
        }
    }
}

// MARK: - Имена событий

/// Имена, которые присылает сервер в поле event.
enum RealtimeEvent {
    static let hello = "hello"
    static let message = "message"
    static let messageSent = "message-sent"
    static let groupMessage = "gmessage"
    static let messageDeleted = "msgdel"
    static let messageEdited = "msgedit"
    static let typing = "typing"
    static let read = "read"
    static let presence = "presence"
    static let notification = "notif"
    static let call = "call"
    static let chatTTL = "chatttl"
    static let post = "post"
    static let update = "update"
}
