import Foundation
import Security
import UIKit

struct SubscriberUsage: Identifiable, Decodable {
    let sessionId: Int
    let hotspot: String
    let countryCode: String?
    let priceLabel: String?
    let priceCreditsPerMiB: String
    let startedAt: String
    let endedAt: String?
    let mib: String
    let chargedCredits: String

    var id: Int { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hotspot
        case countryCode = "country_code"
        case priceLabel = "price_label"
        case priceCreditsPerMiB = "price_credits_per_mib"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case mib
        case chargedCredits = "charged_credits"
    }
}

struct PaymentCapability: Decodable {
    let enabled: Bool
    let reason: String?
}

struct SubscriberAccount: Decodable {
    let customerId: Int
    let email: String?
    let phone: String?
    let balanceCredits: String
    let sessions: [SubscriberUsage]
    let payment: PaymentCapability

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case email, phone, sessions, payment
        case balanceCredits = "balance_credits"
    }
}

private struct LoginResponse: Decodable {
    let ok: Bool
    let token: String
}

private struct APIError: Decodable {
    let ok: Bool?
    let reason: String?
}

enum SubscriberAPIError: LocalizedError {
    case invalidResponse
    case service(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from TaraSec"
        case .service(let message): return message.replacingOccurrences(of: "_", with: " ")
        case .notSignedIn: return "Not signed in"
        }
    }
}

@MainActor
final class SubscriberAccountClient: ObservableObject {
    static let shared = SubscriberAccountClient()
    private let subscriberBaseURL = URL(string: "https://tarasec.org/api/v1/subscriber")!
    private let identityBaseURL = URL(string: "https://tarasec.org/api/v1/identity")!
    private let keychainService = "org.tarasec.app.subscriber"
    private let keychainAccount = "global-subscriber-token"

    @Published var account: SubscriberAccount?

    func identityLoginURL(provider: String) throws -> URL {
        guard provider == "google" || provider == "facebook" else {
            throw SubscriberAPIError.service("Unsupported identity provider")
        }
        var components = URLComponents(url: identityBaseURL.appendingPathComponent("identity-start.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "app_redirect", value: "tarasec://identity")
        ]
        guard let url = components.url else { throw SubscriberAPIError.invalidResponse }
        return url
    }

    func exchangeIdentityCode(_ code: String) async throws {
        guard let deviceKey = UIDevice.current.identifierForVendor?.uuidString.lowercased() else {
            throw SubscriberAPIError.service("iPhone device identity is unavailable")
        }
        var request = URLRequest(url: identityBaseURL.appendingPathComponent("identity-exchange.php"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "device_key": deviceKey,
            "device_label": "iPhone"
        ].map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        try saveToken(response.token)
        try await refresh()
    }

    func login(identifier: String, password: String) async throws {
        var request = URLRequest(url: subscriberBaseURL.appendingPathComponent("subscriber-login.php"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let body = [
            "identifier": identifier,
            "password": password,
            "device_label": "iPhone"
        ].map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let data = try await perform(request)
        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        try saveToken(response.token)
        try await refresh()
    }

    func refresh() async throws {
        guard let token = loadToken() else { throw SubscriberAPIError.notSignedIn }
        var request = URLRequest(url: subscriberBaseURL.appendingPathComponent("subscriber-account.php"))
        request.setValue(token, forHTTPHeaderField: "X-TaraSec-Subscriber-Token")
        let data = try await perform(request)
        account = try JSONDecoder().decode(SubscriberAccount.self, from: data)
    }

    func signOut() {
        deleteToken()
        account = nil
    }

    func hasStoredSession() -> Bool { loadToken() != nil }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SubscriberAPIError.invalidResponse }
        if !(200...299).contains(http.statusCode) {
            let reason = (try? JSONDecoder().decode(APIError.self, from: data).reason) ?? "HTTP \(http.statusCode)"
            throw SubscriberAPIError.service(reason)
        }
        return data
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func saveToken(_ token: String) throws {
        deleteToken()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SubscriberAPIError.service("Unable to store TaraSec session") }
    }

    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
