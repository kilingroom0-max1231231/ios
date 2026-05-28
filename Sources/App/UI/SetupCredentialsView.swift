import SwiftUI

struct SetupCredentialsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(AppColors.accent)
                    Text(AppText.tr("Telegram User Client", "Telegram User Client"))
                        .font(.title2.bold())
                    Text(AppText.tr("Подключение через TDLib", "Connect via TDLib"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                if let bootstrapError = vm.bootstrapError {
                    Label(bootstrapError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(AppText.tr("Данные API", "API credentials"))
                        .font(.headline)

                    Text(AppText.tr("Получите на my.telegram.org → API development tools", "Get them at my.telegram.org → API development tools"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(AppText.tr("API ID", "API ID"), text: $vm.apiIdText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .glassField()

                    TextField(AppText.tr("API Hash", "API Hash"), text: $vm.apiHash)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .glassField()
                }
                .padding()
                .glassContainer(cornerRadius: 22)

                Button {
                    Task { await vm.saveAndConnect() }
                } label: {
                    HStack {
                        if vm.isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(vm.isBusy ? AppText.tr("Подключение…", "Connecting…") : AppText.tr("Продолжить", "Continue"))
                            .fontWeight(.semibold)
                    }
                }
                .glassButton(prominent: false)
                .disabled(vm.isBusy)

                if !vm.status.isEmpty {
                    Text(vm.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .background(ChatListScreenBackground())
    }
}
