import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var apiIdText = ""
    @Published var apiHash = ""
    @Published var phone = ""
    @Published var code = ""
    @Published var password = ""

    @Published var chats: [TgChat] = []
    @Published var selectedChatId: Int64?
    @Published var messages: [TgMessage] = []
    @Published var composeText = ""
    @Published var status = "Введи api_id и api_hash"
    @Published var authState: AuthState = .waitPhone
    @Published var isBusy = false

    private let repository = TelegramRepository()

    init() {
        repository.onAuthStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.authState = state
                if state != .ready {
                    self?.status = "Следующий шаг авторизации: \(self?.authStateLabel(state) ?? "")"
                }
            }
        }

        repository.onMessagesChanged = { [weak self] chatId in
            guard let self else { return }
            Task { @MainActor in
                if self.selectedChatId == chatId {
                    await self.refreshMessages()
                }
            }
        }

        repository.onChatsChanged = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    self.chats = try await self.repository.loadChats()
                } catch {
                    self.status = "Ошибка списка чатов: \(error.localizedDescription)"
                }
            }
        }
    }

    func setupClient() async {
        guard let apiId = Int(apiIdText.trimmingCharacters(in: .whitespacesAndNewlines)),
              !apiHash.isEmpty else {
            status = "Некорректный api_id/api_hash"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.setup(apiId: apiId, apiHash: apiHash)
            authState = repository.authState()
            status = "TDLib инициализирован"
        } catch {
            status = "Ошибка инициализации: \(error.localizedDescription)"
        }
    }

    func submitAuth() async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch authState {
            case .waitPhone:
                try await repository.submitPhone(phone)
            case .waitCode:
                try await repository.submitCode(code)
            case .waitPassword:
                try await repository.submitPassword(password)
            case .ready:
                break
            }
            authState = repository.authState()
            if authState == .ready {
                status = "Авторизация готова"
                chats = try await repository.loadChats()
                selectedChatId = chats.first?.id
                if let selectedChatId {
                    messages = try await repository.syncMessages(chatId: selectedChatId)
                }
            } else {
                status = "Следующий шаг авторизации: \(authStateLabel(authState))"
            }
        } catch {
            status = "Ошибка auth: \(error.localizedDescription)"
        }
    }

    func selectChat(_ chatId: Int64) async {
        selectedChatId = chatId
        await refreshMessages()
    }

    func refreshMessages() async {
        guard let chatId = selectedChatId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            messages = try await repository.syncMessages(chatId: chatId)
            status = "Сообщения обновлены"
        } catch {
            status = "Ошибка чтения: \(error.localizedDescription)"
        }
    }

    func sendMessage() async {
        guard let chatId = selectedChatId else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            messages = try await repository.send(chatId: chatId, text: text)
            composeText = ""
            status = "Отправлено"
        } catch {
            status = "Ошибка отправки: \(error.localizedDescription)"
        }
    }

    func downloadMedia() async {
        guard let chatId = selectedChatId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            messages = try await repository.downloadMedia(chatId: chatId)
            status = "Медиа загружены локально"
        } catch {
            status = "Ошибка загрузки медиа: \(error.localizedDescription)"
        }
    }

    func authStateLabel(_ state: AuthState) -> String {
        switch state {
        case .waitPhone: return "номер телефона"
        case .waitCode: return "код из Telegram"
        case .waitPassword: return "пароль 2FA"
        case .ready: return "готово"
        }
    }
}
