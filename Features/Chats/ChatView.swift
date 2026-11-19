import SwiftUI

struct ChatView: View {

    let peerID: Int
    /// Вызывается при открытии, чтобы сбросить счётчик непрочитанных в списке.
    var onOpen: (() -> Void)? = nil

    @State private var viewModel: ChatViewModel
    @State private var text = ""
    @State private var isPickerPresented = false

    @FocusState private var isFocused: Bool

    init(peerID: Int, onOpen: (() -> Void)? = nil) {
        self.peerID = peerID
        self.onOpen = onOpen
        _viewModel = State(initialValue: ChatViewModel(peerID: peerID))
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            replyBar
            composer
        }
        .navigationTitle(viewModel.peer?.name ?? "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                header
            }
        }
        .task {
            await viewModel.load()
            onOpen?()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glimIncomingMessage)) { note in
            guard let payload = note.object as? IncomingMessagePayload,
                  payload.user.id == peerID else { return }
            viewModel.receive(payload.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .glimTyping)) { note in
            guard let payload = note.object as? TypingPayload,
                  payload.peerID == peerID else { return }
            viewModel.peerIsTyping()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glimReadReceipt)) { note in
            guard let payload = note.object as? ReadPayload,
                  payload.peerID == peerID else { return }
            viewModel.markRead()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glimMessagesDeleted)) { note in
            guard let payload = note.object as? DeletedPayload,
                  payload.peerID == peerID else { return }
            viewModel.applyDelete(ids: payload.ids)
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(spacing: 1) {
            Text(viewModel.peer?.name ?? "")
                .font(.headline)

            if viewModel.isPeerTyping {
                Text("печатает…")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            } else if viewModel.peer?.online == true {
                Text("в сети")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Сообщения

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.canLoadMore {
                        ProgressView()
                            .padding(.vertical, 8)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, peer: viewModel.peer)
                            .id(message.id)
                            .contextMenu {
                                Button {
                                    viewModel.replyTo = message
                                } label: {
                                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                                }

                                if message.me, message.kind == .text {
                                    Button {
                                        // Редактирование: подставляем текст в поле.
                                        text = message.text
                                        isFocused = true
                                    } label: {
                                        Label("Изменить", systemImage: "pencil")
                                    }
                                }

                                Button(role: .destructive) {
                                    Task { await viewModel.delete(message: message) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.messages.count) {
                // Новое сообщение — прокручиваем вниз.
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Ответ

    @ViewBuilder
    private var replyBar: some View {
        if let reply = viewModel.replyTo {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.me ? "Вы" : (viewModel.peer?.name ?? ""))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)

                    Text(reply.text.isEmpty ? reply.kind.preview : reply.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    viewModel.replyTo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
        }
    }

    // MARK: - Поле ввода

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                isPickerPresented = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .focused($isFocused)
                .onChange(of: text) {
                    if !text.isEmpty { viewModel.notifyTyping() }
                }

            Button {
                let outbound = text
                text = ""
                Task { await viewModel.send(text: outbound) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog("Вложение", isPresented: $isPickerPresented) {
            Button("Фото или видео") {
                // TODO: PhotosPicker + загрузка через .upload(kind:fileName:data:)
            }
            Button("Файл") {
                // TODO: fileImporter + загрузка
            }
            Button("Голосовое") {
                // TODO: запись через AVAudioRecorder
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
