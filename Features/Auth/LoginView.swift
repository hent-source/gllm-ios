import SwiftUI

struct LoginView: View {

    @State private var viewModel = AuthViewModel()
    private let session = SessionStore.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Glim")
                .font(.system(size: 44, weight: .bold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                fields
            }
            .padding(.horizontal)

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            primaryButton

            secondaryButton

            Spacer()
        }
        .animation(.default, value: viewModel.step)
    }

    // MARK: - Текст над полями

    private var subtitle: String {
        switch viewModel.step {
        case .email:
            return "Введите почту — пришлём код для входа"
        case .code:
            return "Код отправлен на \(viewModel.maskedDestination)"
        case .profile:
            return "Расскажите о себе"
        case .password:
            return viewModel.passwordHint.isEmpty
                ? "Введите облачный пароль"
                : "Подсказка: \(viewModel.passwordHint)"
        case .totp:
            return "Введите код из приложения-аутентификатора"
        case .backup:
            return "Введите резервный код"
        }
    }

    // MARK: - Поля

    @ViewBuilder
    private var fields: some View {
        switch viewModel.step {
        case .email:
            field("Почта", text: $viewModel.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

        case .code:
            field("Код из письма", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

        case .profile:
            field("Имя", text: $viewModel.name)
                .textContentType(.name)

            HStack {
                field("Ник", text: $viewModel.handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.handle) {
                        Task { await viewModel.checkHandle() }
                    }

                if let available = viewModel.isHandleAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(available ? .green : .red)
                }
            }

            field("О себе (необязательно)", text: $viewModel.bio)

        case .password:
            secureField("Пароль", text: $viewModel.password)

        case .totp, .backup:
            field("Код", text: $viewModel.password)
                .keyboardType(.numberPad)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Кнопки

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(primaryTitle).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canSubmit)
        .padding(.horizontal)
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .email:   return "Получить код"
        case .code:    return "Продолжить"
        case .profile: return "Создать аккаунт"
        default:       return "Войти"
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        switch viewModel.step {
        case .code, .profile, .password, .totp, .backup:
            Button("Назад") {
                viewModel.backToEmail()
            }
            .font(.footnote)
        case .email:
            EmptyView()
        }
    }

    // MARK: - Действия

    private func submit() async {
        switch viewModel.step {
        case .email:
            await viewModel.submitEmail()

        case .code:
            await viewModel.submitCode()

        case .profile:
            if let user = await viewModel.submitProfile() {
                session.signIn(as: user)
            }

        case .password, .totp, .backup:
            if let user = await viewModel.submitSecret() {
                session.signIn(as: user)
            }
        }
    }
}
