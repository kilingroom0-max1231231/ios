import Contacts
import Foundation

enum DeviceContactsAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct DeviceContactEntry: Equatable {
    let phone: String
    let firstName: String
    let lastName: String
}

enum DeviceContactsService {
    static func authorizationStatus() -> DeviceContactsAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notDetermined
        case .authorized, .limited: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func requestAccess() async -> Bool {
        let store = CNContactStore()
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    static func fetchEntries() async throws -> [DeviceContactEntry] {
        guard authorizationStatus() == .authorized else { return [] }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var entries: [DeviceContactEntry] = []
        let store = CNContactStore()
        try store.enumerateContacts(with: request) { contact, _ in
            let firstName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            for phoneValue in contact.phoneNumbers {
                guard let normalized = normalizePhone(phoneValue.value.stringValue) else { continue }
                entries.append(
                    DeviceContactEntry(
                        phone: normalized,
                        firstName: firstName.isEmpty ? lastName : firstName,
                        lastName: firstName.isEmpty ? "" : lastName
                    )
                )
            }
        }
        return entries
    }

    static func normalizePhone(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }
        if raw.hasPrefix("+") {
            return "+\(digits)"
        }
        return "+\(digits)"
    }
}
