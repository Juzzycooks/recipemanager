import Foundation
import Observation

/// Who is signed in, and the client to talk to the server with. Injected into the environment.
@MainActor @Observable
final class Session {
    private(set) var user: User?
    private(set) var baseURL: URL?
    private var token: String?
    private(set) var isRestoring = false

    /// Bumped whenever recipes change so the shelf reloads (create, edit, delete, undo).
    private(set) var dataVersion = 0
    /// The most recently deleted recipe, offered for undo.
    private(set) var deleted: DeletedRecipe?

    struct DeletedRecipe: Equatable { let title: String; let token: String }

    private let defaults = UserDefaults.standard
    private static let serverKey = "serverURL"

    var isSignedIn: Bool { user != nil }
    var lastServer: String { defaults.string(forKey: Self.serverKey) ?? "" }

    init() {
        if let saved = defaults.string(forKey: Self.serverKey), let url = URL(string: saved), let token = Keychain.read() {
            baseURL = url
            self.token = token
            isRestoring = true
            Task { await restore() }
        }
    }

    var client: APIClient? {
        guard let baseURL else { return nil }
        return APIClient(baseURL: baseURL, token: token)
    }

    /// Runs a request; a 401 signs the user out (token revoked elsewhere).
    func run<T: Sendable>(_ operation: @Sendable (APIClient) async throws -> T) async throws -> T {
        guard let client else { throw APIError.unauthorized }
        do { return try await operation(client) }
        catch APIError.unauthorized {
            signOutLocally()
            throw APIError.unauthorized
        }
    }

    func recipesChanged() { dataVersion += 1 }

    func recipeDeleted(title: String, token: String) {
        deleted = DeletedRecipe(title: title, token: token)
        recipesChanged()
    }

    func dismissDeleted(_ token: String) { if deleted?.token == token { deleted = nil } }

    func undoDelete() async {
        guard let deleted else { return }
        self.deleted = nil
        let token = deleted.token
        _ = try? await run { client in
            let _: RecipeDetail = try await client.send("POST", "/recipes/restore/\(token)")
        }
        recipesChanged()
    }

    /// Re-reads the signed-in user (after changing the email, for example).
    func refreshUser() async {
        if let fresh: User = try? await run({ try await $0.get("/me") }) { user = fresh }
    }

    func imageURL(_ path: String) -> URL? { client?.resolve(path) }

    // MARK: Sign in / out

    nonisolated static func normalise(server: String) -> URL? {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    func signIn(server: String, username: String, password: String) async throws {
        guard let url = Self.normalise(server: server) else { throw APIError.invalidServer }
        let anonymous = APIClient(baseURL: url, token: nil)
        struct Body: Encodable, Sendable { let username: String; let password: String; let deviceName: String }
        let device = "iOS app"
        let response: LoginResponse = try await anonymous.send("POST", "/auth/login",
                                                              body: Body(username: username, password: password, deviceName: device))
        Keychain.write(response.token)
        defaults.set(url.absoluteString, forKey: Self.serverKey)
        baseURL = url
        token = response.token
        user = response.user
    }

    func signOut() async {
        if let client { try? await client.send("POST", "/auth/logout") }
        signOutLocally()
    }

    private func signOutLocally() {
        Keychain.delete()
        token = nil
        user = nil
    }

    private func restore() async {
        defer { isRestoring = false }
        guard let client else { return }
        do { user = try await client.get("/me") }
        catch APIError.unauthorized { signOutLocally() }
        catch { // offline: keep the token, show the app once the network is back
            user = nil
            token = Keychain.read()
            offlineRestore = true
        }
    }

    /// True when the token is kept but the server couldn't be reached at launch.
    private(set) var offlineRestore = false

    func retryRestore() async {
        isRestoring = true
        offlineRestore = false
        await restore()
    }
}
