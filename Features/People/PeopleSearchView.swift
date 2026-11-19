import SwiftUI
import Observation

struct PeopleSearchView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.glimRouter) private var router

    @State private var viewModel = PeopleViewModel()
    var onPick: ((User) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.query.isEmpty {
                    suggestions
                } else if viewModel.results.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                } else {
                    results
                }
            }
            .navigationTitle("Люди")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Имя или @ник")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                await viewModel.loadSuggestions()
            }
            .onChange(of: viewModel.query) {
                Task { await viewModel.search() }
            }
        }
    }

    private var suggestions: some View {
        List {
            if !viewModel.results.isEmpty {
                Section("Кого можно знать") {
                    ForEach(viewModel.results) { user in
                        row(for: user)
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
            }
        }
        .listStyle(.plain)
    }

    private var results: some View {
        List {
            ForEach(viewModel.results) { user in
                row(for: user)
            }
        }
        .listStyle(.plain)
    }

    private func row(for user: User) -> some View {
        Button {
            // В режиме выбора отдаём человека наружу,
            // иначе открываем переписку с ним.
            if let onPick {
                onPick(user)
            } else {
                dismiss()
                router.open(chat: user.id)
            }
        } label: {
            HStack(spacing: 12) {
                CachedAvatar(url: user.avatarURL, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if user.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("@\(user.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if user.isFollowing {
                    Text("подписан")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Модель поиска

@Observable
@MainActor
final class PeopleViewModel {

    var query = ""
    private(set) var results: [User] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func loadSuggestions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.send(.users(), as: UsersResponse.self)
            results = response.users
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    /// Поиск с небольшой задержкой, чтобы не дёргать сервер на каждую букву.
    func search() async {
        searchTask?.cancel()

        let value = query.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else {
            await loadSuggestions()
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            isLoading = true
            defer { isLoading = false }

            do {
                let response = try await APIClient.shared.send(
                    .users(query: value),
                    as: UsersResponse.self
                )
                guard !Task.isCancelled else { return }
                results = response.users
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? APIError)?.errorDescription
            }
        }
    }
}
