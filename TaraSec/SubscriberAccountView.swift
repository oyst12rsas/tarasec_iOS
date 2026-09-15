import SwiftUI

struct SubscriberAccountView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var client = SubscriberAccountClient.shared
    @State private var identifier = ""
    @State private var password = ""
    @State private var status = "Not signed in to a global TaraSec account."
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let account = client.account {
                    Section("My TaraSec account") {
                        Text(account.email ?? account.phone ?? "TaraSec subscriber")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Balance").font(.caption)
                            Text("\(account.balanceCredits) credits").font(.title2)
                            Text("Credits are global. The amount of data they buy depends on the hotspot price.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh") { Task { await refresh() } }
                        Button("Sign out", role: .destructive) {
                            client.signOut()
                            status = "Signed out."
                        }
                        Button(account.payment.enabled ? "Add credits / Pay" : "Payments coming next") { }
                            .disabled(!account.payment.enabled)
                    }

                    Section("Recent hotspot usage") {
                        if account.sessions.isEmpty {
                            Text("No TaraSec hotspot usage recorded yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(account.sessions) { usage in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(usage.hotspot).font(.headline)
                                    if let label = usage.priceLabel { Text(label).font(.caption) }
                                    Text("\(usage.mib) MiB · \(usage.chargedCredits) credits")
                                    Text("Rate: \(usage.priceCreditsPerMiB) credits/MiB")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Section("Global TaraSec sign in") {
                        Text("Sign in with a global identity. This grants subscriber access only; node-management approval remains local.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Continue with Google") { startIdentityLogin("google") }
                            .disabled(loading)
                        Button("Continue with Facebook") { startIdentityLogin("facebook") }
                            .disabled(loading)
                        Text("Or use an existing TaraSec password").font(.caption)
                        TextField("Email or phone", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        SecureField("Password", text: $password)
                        Button(loading ? "Signing in..." : "Sign in to TaraSec") {
                            Task { await login() }
                        }
                        .disabled(loading || identifier.isEmpty || password.isEmpty)
                    }
                }

                Section {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("TaraSec")
            .task {
                if client.account == nil && client.hasStoredSession() {
                    await refresh()
                }
            }
            .onOpenURL { url in
                guard url.scheme == "tarasec", url.host == "identity",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
                Task { await exchangeIdentityCode(code) }
            }
        }
    }

    private func startIdentityLogin(_ provider: String) {
        do {
            openURL(try client.identityLoginURL(provider: provider))
        } catch {
            status = error.localizedDescription
        }
    }

    private func exchangeIdentityCode(_ code: String) async {
        loading = true
        defer { loading = false }
        do {
            try await client.exchangeIdentityCode(code)
            status = "Signed in to global TaraSec account."
        } catch {
            status = error.localizedDescription
        }
    }

    private func login() async {
        loading = true
        defer { loading = false }
        do {
            try await client.login(identifier: identifier, password: password)
            password = ""
            status = "Signed in to global TaraSec account."
        } catch {
            status = error.localizedDescription
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            try await client.refresh()
            status = "Global TaraSec account connected."
        } catch {
            client.signOut()
            status = error.localizedDescription
        }
    }
}
