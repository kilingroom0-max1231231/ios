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
                    Text("Telegram User Client")
                        .font(.title2.bold())
                    Text("Подключение через TDLib")
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
                    Text("API credentials")
                        .font(.headline)

                    Text("Получите на my.telegram.org → API development tools")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("API ID", text: $vm.apiIdText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .glassField()

                    TextField("API Hash", text: $vm.apiHash)
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
                        Text(vm.isBusy ? "Подключение…" : "Продолжить")
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
        .background(AppColors.screenBackground)
    }
}
