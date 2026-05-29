import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatAttachmentMenu: View {
    let onPhoto: () -> Void
    let onFile: () -> Void
    let onSticker: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            row(icon: "photo", title: AppText.tr("Фото", "Photo"), action: onPhoto)
            row(icon: "doc", title: AppText.tr("Файл", "File"), action: onFile)
            row(icon: "face.smiling", title: AppText.tr("Стикер", "Sticker"), action: onSticker)
        }
        .padding(20)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 36)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageData: (Data) -> Void
        let dismiss: DismissAction

        init(onImageData: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onImageData = onImageData
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.88) else { return }
                DispatchQueue.main.async {
                    self.onImageData(data)
                }
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping (URL) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            dismiss()
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }
    }
}

struct VideoNoteCameraPicker: UIViewControllerRepresentable {
    let onVideoURL: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraDevice = .front
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoURL: onVideoURL, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onVideoURL: (URL) -> Void
        let dismiss: DismissAction

        init(onVideoURL: @escaping (URL) -> Void, dismiss: DismissAction) {
            self.onVideoURL = onVideoURL
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            dismiss()
            if let url = info[.mediaURL] as? URL {
                onVideoURL(url)
            }
        }
    }
}

struct StickerPickerView: View {
    @ObservedObject var vm: AppViewModel
    let onSelect: (TgSticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.stickerSearchResults.isEmpty && !vm.isStickerSearchLoading {
                    Text(AppText.tr("Введите запрос или потяните для обновления", "Type to search stickers"))
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(vm.stickerSearchResults) { sticker in
                            Button {
                                onSelect(sticker)
                                dismiss()
                            } label: {
                                StickerMediaView(
                                    displayPath: sticker.displayPath,
                                    animationPath: sticker.animationPath,
                                    isAnimated: sticker.isAnimated,
                                    playbackMode: .staticPreview,
                                    maxSide: 64
                                )
                                .frame(width: 72, height: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
            .navigationTitle(AppText.tr("Стикеры", "Stickers"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: AppText.tr("Поиск", "Search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Закрыть", "Close")) { dismiss() }
                }
            }
            .task { await vm.loadDefaultStickers() }
            .onChange(of: query) { value in
                Task { await vm.searchStickers(query: value) }
            }
            .overlay {
                if vm.isStickerSearchLoading && vm.stickerSearchResults.isEmpty {
                    ProgressView()
                }
            }
        }
    }
}

struct MessageReactionPicker: View {
    let emojis: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .presentationDetents([.height(100)])
        .presentationDragIndicator(.visible)
    }
}

struct VoiceRecordingOverlay: View {
    @ObservedObject var recorder: VoiceNoteRecorder
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(formattedElapsed)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(AppText.tr("Запись…", "Recording…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accent, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassContainer(cornerRadius: 22)
        .padding(.horizontal, 10)
    }

    private var formattedElapsed: String {
        let total = Int(recorder.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
