import SwiftUI

struct ChatsView: View {

    @State private var viewModel = ChatsViewModel()
    @State private var isSearchPresented = false
    @State private var openChatID: Int?

    @Environment(\.glimRouter) private var router

    private let realtime = RealtimeService.shared

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.chats.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.chats.isEmpty, let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Чаты недоступны", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") {
                            Task { await viewModel.load() }
                        }
                    }
                } else if viewModel.chats.isEmpty {
                    ContentUnavailableView {
                        Label("Пока пусто", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Начните переписку: найдите человека в поиске")
                    } actions: {
                        Button("Найти людей") { isSearchPresented = true }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Чаты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(item: $openChatID) { id in
                ChatView(peerID: id) {
                    viewModel.clearUnread(peerID: id)
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                PeopleSearchView()
            }
            .task {
                await viewModel.load()
                await realtime.ensureRunning()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glimIncomingMessage)) { note in
                guard let payload = note.object as? IncomingMessagePayload else { return }
                viewModel.apply(incoming: payload.message, from: payload.user)
            }
            .onChange(of: router.pending) {
                // Переход из другой вкладки: открыть переписку с найденным человеком.
                // takePending отдаёт задачу один раз — повторно она не сработает.
                if case .chat(let peerID) = router.takePending(for: .chats) {
                    openChatID = peerID
                }
            }
            .onAppear {
                // Если переход случился до появления этого экрана —
                // забираем задачу сразу, onChange уже не сработает.
                if case .chat(let peerID) = router.takePending(for: .chats) {
                    openChatID = peerID
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.chats) { chat in
                Button {
                    openChatID = chat.user.id
                    viewModel.clearUnread(peerID: chat.user.id)
                } label: {
                    ChatRow(chat: chat)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.load()
        }
    }
}

// MARK: - Строка чата

struct ChatRow: View {

    let chat: ChatSummary

    private let realtime = RealtimeService.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CachedAvatar(url: chat.user.avatarURL, size: 52)

                if realtime.onlineUsers.contains(chat.user.id) || chat.user.online {
                    Circle()
                        .fill(.green)
                        .frame(width: 13, height: 13)
                        .overlay {
                            Circle().stroke(Color(.systemBackground), lineWidth: 2)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(chat.user.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if chat.user.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    if let last = chat.last {
                        Text(last.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    if let last = chat.last, last.me {
                        Image(systemName: last.isRead ? "checkmark.circle.fill" : "checkmark")
                            .font(.caption2)
                            .foregroundStyle(last.isRead ? Color.accentColor : .secondary)
                    }

                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if chat.unread > 0 {
                        Text("\(chat.unread)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var preview: String {
        guard let last = chat.last else { return "Нет сообщений" }
        if !last.text.isEmpty { return last.text }
        return last.kind.preview
    }
}
