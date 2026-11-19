import SwiftUI

struct FeedView: View {

    @State private var viewModel = FeedViewModel()
    @State private var isComposerPresented = false

    private let tabs: [(title: String, tab: FeedTab?)] = [
        ("Для вас", nil),
        ("Подписки", .following),
        ("Новое", .latest),
        ("Сохранённое", .saved)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                content
            }
            .navigationTitle("Glim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposerPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $isComposerPresented) {
                ComposerView { post in
                    viewModel.prepend(post)
                }
            }
            .task {
                await viewModel.load(reset: true)
            }
        }
    }

    // MARK: - Переключатель разделов

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.title) { item in
                    let isSelected = viewModel.tab == item.tab
                    Button {
                        viewModel.tab = item.tab
                    } label: {
                        Text(item.title)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? Color(.secondarySystemBackground)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Список

    @ViewBuilder
    private var content: some View {
        if viewModel.posts.isEmpty && viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.posts.isEmpty, let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Лента недоступна", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Повторить") {
                    Task { await viewModel.refresh() }
                }
            }
        } else if viewModel.posts.isEmpty {
            ContentUnavailableView {
                Label("Здесь пока пусто", systemImage: "text.bubble")
            } description: {
                Text(emptyDescription)
            }
        } else {
            List {
                ForEach(viewModel.posts) { post in
                    PostRowView(
                        post: post,
                        onReact: { emoji in
                            Task { await viewModel.react(to: post, emoji: emoji) }
                        },
                        onSave: {
                            Task { await viewModel.toggleSave(on: post) }
                        },
                        onRepost: {
                            Task { await viewModel.toggleRepost(on: post) }
                        },
                        onVote: { option in
                            Task { await viewModel.vote(on: post, option: option) }
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .task {
                        await viewModel.loadMoreIfNeeded(current: post)
                    }
                }

                if viewModel.canLoadMore && !viewModel.posts.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var emptyDescription: String {
        switch viewModel.tab {
        case .following: return "Подпишитесь на кого-нибудь, и здесь появятся их записи"
        case .saved:     return "Сохраняйте записи, чтобы вернуться к ним позже"
        case .latest:    return "Пока никто ничего не опубликовал"
        default:         return "Рекомендаций пока нет"
        }
    }
}

// MARK: - Создание поста

struct ComposerView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var onPublished: (Post) -> Void

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Что нового?")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Сервер ограничивает длину поста: 500 символов, 2000 для премиума.
                Text("\(text.count) / 500")
                    .font(.caption)
                    .foregroundStyle(text.count > 500 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer()
            }
            .padding()
            .navigationTitle("Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Опубликовать").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSend)
                }
            }
        }
    }

    private func publish() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let response = try await APIClient.shared.send(
                .createPost(CreatePostRequest(text: text.trimmingCharacters(in: .whitespacesAndNewlines))),
                as: PostResponse.self
            )
            onPublished(response.post)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось опубликовать"
        }
    }
}
