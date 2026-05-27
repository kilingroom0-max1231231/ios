import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GroupBox("TDLib") {
                    VStack(spacing: 8) {
                        TextField("api_id", text: $vm.apiIdText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("api_hash", text: $vm.apiHash)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Init TDLib") {
                            Task { await vm.setupClient() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                GroupBox("Авторизация (\(vm.authStateLabel(vm.authState)))") {
                    VStack(spacing: 8) {
                        TextField("phone (+7999...)", text: $vm.phone)
                            .textFieldStyle(.roundedBorder)
                        if vm.authState == .waitCode {
                            TextField("code", text: $vm.code)
                                .textFieldStyle(.roundedBorder)
                        }
                        if vm.authState == .waitPassword {
                            SecureField("2FA password", text: $vm.password)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("Продолжить") {
                            Task { await vm.submitAuth() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)

                if !vm.chats.isEmpty {
                    Picker("Чат", selection: Binding(get: {
                        vm.selectedChatId ?? vm.chats.first?.id ?? 0
                    }, set: { newValue in
                        Task { await vm.selectChat(newValue) }
                    })) {
                        ForEach(vm.chats) { chat in
                            Text(chat.title).tag(chat.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                }

                HStack {
                    Button("Обновить") { Task { await vm.refreshMessages() } }
                        .buttonStyle(.bordered)
                    Button("Скачать медиа") { Task { await vm.downloadMedia() } }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text(vm.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List(vm.messages) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(msg.outgoing ? "Ты" : "Собеседник")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(msg.isDeleted ? "[Удалено локально сохранено]" : msg.text)
                            .foregroundStyle(msg.isDeleted ? .red : .primary)

                        if !msg.attachments.isEmpty {
                            ForEach(msg.attachments) { attachment in
                                Text(attachmentLabel(attachment))
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                HStack {
                    TextField("Сообщение", text: $vm.composeText)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {
                        Task { await vm.sendMessage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy)
                }
                .padding()
            }
            .navigationTitle("Telegram User Client")
        }
    }

    private func attachmentLabel(_ attachment: TgAttachment) -> String {
        var text = "[\(attachment.kind.rawValue)]"
        if let fileName = attachment.fileName, !fileName.isEmpty {
            text += " \(fileName)"
        }
        if let size = attachment.size {
            text += " (\(size) bytes)"
        }
        if let path = attachment.localPath, !path.isEmpty {
            text += " -> \(path)"
        }
        return text
    }
}
