import SwiftUI

struct RootView: View {

    private let session = SessionStore.shared
    @State private var router = Router()

    var body: some View {
        Group {
            if session.isRestoring {
                // Пока проверяем сохранённую сессию, показываем заглушку,
                // чтобы экран входа не мелькал при каждом запуске.
                ProgressView()
                    .controlSize(.large)
            } else if session.isAuthorized {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environment(\.glimRouter, router)
        .animation(.default, value: session.isAuthorized)
        .task {
            await session.restore()
            // Realtime поднимаем сразу после входа: он нужен и чатам,
            // и уведомлениям, и статусам «в сети».
            if session.isAuthorized {
                await RealtimeService.shared.ensureRunning()
            }
        }
        .onChange(of: session.isAuthorized) { _, isAuthorized in
            Task {
                if isAuthorized {
                    await RealtimeService.shared.ensureRunning()
                } else {
                    RealtimeService.shared.stop()
                }
            }
        }
    }
}

struct MainTabView: View {

    @Environment(\.glimRouter) private var router

    var body: some View {
        TabView(selection: Bindable(router).selectedTab) {
            FeedView()
                .tabItem {
                    Label("Лента", systemImage: "house")
                }
                .tag(Router.Tab.feed)

            ChatsView()
                .tabItem {
                    Label("Чаты", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Router.Tab.chats)

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person")
                }
                .tag(Router.Tab.profile)
        }
    }
}
