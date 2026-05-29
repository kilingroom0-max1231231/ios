import AVFoundation
import Foundation
import UIKit

enum MediaCaptureError: LocalizedError {
    case microphoneDenied
    case cameraDenied
    case recorderUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Нет доступа к микрофону"
        case .cameraDenied: return "Нет доступа к камере"
        case .recorderUnavailable: return "Не удалось начать запись"
        case .exportFailed: return "Не удалось сохранить медиа"
        }
    }
}

@MainActor
final class VoiceNoteRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw MediaCaptureError.recorderUnavailable
        }
        self.recorder = recorder
        outputURL = url
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsed += 0.1
            }
        }
    }

    func stop() -> (url: URL, duration: Int, waveform: [Int])? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        isRecording = false
        defer {
            recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard let url = outputURL else { return nil }
        let duration = max(1, Int(ceil(elapsed)))
        let waveform = generateWaveform(from: recorder)
        return (url, duration, waveform)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func generateWaveform(from recorder: AVAudioRecorder?) -> [Int] {
        guard let recorder else { return Array(repeating: 12, count: 32) }
        recorder.updateMeters()
        var samples: [Int] = []
        samples.reserveCapacity(32)
        for index in 0..<32 {
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(4, min(31, Int((power + 50) * 31 / 50)))
            _ = index
            samples.append(normalized)
        }
        return samples
    }
}

enum OutgoingMediaFile {
    case photo(URL)
    case document(URL, fileName: String, mimeType: String?)
    case voice(URL, duration: Int, waveform: [Int])
    case videoNote(URL, duration: Int)

    func copyToUploadsDirectory() throws -> URL {
        let ext: String
        switch self {
        case .photo: ext = "jpg"
        case .document(let url, _, _): ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        case .voice: ext = "m4a"
        case .videoNote: ext = "mp4"
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        switch self {
        case .photo(let url), .voice(let url, _, _), .videoNote(let url, _):
            try FileManager.default.copyItem(at: url, to: destination)
        case .document(let url, _, _):
            try FileManager.default.copyItem(at: url, to: destination)
        }
        return destination.standardizedFileURL
    }
}

enum MediaFileImporter {
    static func persistPhotoData(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url.standardizedFileURL
    }

    static func persistPickedFile(_ source: URL) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-\(UUID().uuidString).\(ext)")
        if source.startAccessingSecurityScopedResource() {
            defer { source.stopAccessingSecurityScopedResource() }
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination.standardizedFileURL
    }
}
