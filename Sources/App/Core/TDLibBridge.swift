import Foundation

// TDLib C API symbols from tdjson.
@_silgen_name("td_json_client_create")
private func td_json_client_create() -> UnsafeMutableRawPointer?

@_silgen_name("td_json_client_send")
private func td_json_client_send(_ client: UnsafeMutableRawPointer?, _ request: UnsafePointer<CChar>?)

@_silgen_name("td_json_client_receive")
private func td_json_client_receive(_ client: UnsafeMutableRawPointer?, _ timeout: Double) -> UnsafePointer<CChar>?

@_silgen_name("td_json_client_execute")
private func td_json_client_execute(_ client: UnsafeMutableRawPointer?, _ request: UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

@_silgen_name("td_json_client_destroy")
private func td_json_client_destroy(_ client: UnsafeMutableRawPointer?)

enum TDLibBridgeError: Error {
    case createFailed
}

final class TDLibBridge {
    private let client: UnsafeMutableRawPointer

    init() throws {
        guard let client = td_json_client_create() else {
            throw TDLibBridgeError.createFailed
        }
        self.client = client
    }

    deinit {
        td_json_client_destroy(client)
    }

    func send(_ payload: String) {
        payload.withCString { ptr in
            td_json_client_send(client, ptr)
        }
    }

    func receive(timeout: Double = 0.1) -> String? {
        guard let response = td_json_client_receive(client, timeout) else {
            return nil
        }
        return String(cString: response)
    }

    func execute(_ payload: String) -> String? {
        payload.withCString { ptr in
            guard let response = td_json_client_execute(client, ptr) else { return nil }
            return String(cString: response)
        }
    }
}
