import Foundation
import Lottie
import zlib

enum TGSFileLoader {
    private static let lock = NSLock()
    private static var animationCache: [String: LottieAnimation] = [:]
    private static let maxCachedAnimations = 24
    /// Telegram `.tgs` stickers are gzip-compressed Lottie JSON.
    static func lottieJSONData(path: String) -> Data? {
        guard path.lowercased().hasSuffix(".tgs") else { return nil }
        guard let compressed = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return gunzip(compressed)
    }

    static func isTGSPath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return URL(fileURLWithPath: path).pathExtension.lowercased() == "tgs"
    }

    /// Writes decompressed Lottie JSON next to the `.tgs` file (reused on next launch).
    static func cachedLottieJSONPath(forTGSPath path: String) -> String? {
        let jsonURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return jsonURL.path
        }
        guard let json = lottieJSONData(path: path) else { return nil }
        do {
            try json.write(to: jsonURL, options: .atomic)
            return jsonURL.path
        } catch {
            return nil
        }
    }

    static func cachedLottieAnimation(forTGSPath path: String) -> LottieAnimation? {
        lock.lock()
        if let cached = animationCache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let jsonPath = cachedLottieJSONPath(forTGSPath: path),
              let animation = LottieAnimation.filepath(jsonPath) else {
            return nil
        }

        lock.lock()
        if animationCache.count >= maxCachedAnimations, let key = animationCache.keys.first {
            animationCache.removeValue(forKey: key)
        }
        animationCache[path] = animation
        lock.unlock()
        return animation
    }

    static func clearAnimationCache() {
        lock.lock()
        animationCache.removeAll()
        lock.unlock()
    }

    private static func gunzip(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }

        return data.withUnsafeBytes { inputBuffer -> Data? in
            guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else { return nil }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer(mutating: inputBase)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(
                &stream,
                MAX_WBITS + 32,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else { return nil }
            defer { inflateEnd(&stream) }

            let chunkSize = 32_768
            var output = Data()

            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let inflateStatus: Int32 = chunk.withUnsafeMutableBytes { rawBuffer in
                    guard let outBase = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return -1 }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
                if inflateStatus == Z_STREAM_END {
                    return output
                }
                if inflateStatus != Z_OK {
                    return nil
                }
            } while stream.avail_out == 0

            return output
        }
    }
}
