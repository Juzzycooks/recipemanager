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
        if let saved = CredentialStore.read(), let url = URL(string: saved.server) {
            baseURL = url
            token = saved.token
            isRestoring = true
            Task { await restore() }
        }
    }

    var client: APIClient? {
        guard let baseURL else { return nil }
        return APIClient(baseURL: baseURL, token: token, cache: OfflineStore.shared)
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
        CredentialStore.write(Credentials(server: url.absoluteString, token: response.token))
        defaults.set(url.absoluteString, forKey: Self.serverKey)   // only to prefill the sign-in screen next time
        await OfflineStore.shared.clear()                          // never show a previous account's data
        Outbox.shared.clear()
        baseURL = url
        token = response.token
        user = response.user
        _ = try? await client?.get("/me") as User?                 // saved now so the app can start offline later
        watchConnectivity()
    }

    func signOut() async {
        if let client { try? await client.send("POST", "/auth/logout") }
        signOutLocally()
    }

    private func signOutLocally() {
        CredentialStore.delete()
        token = nil
        user = nil
        Task { await OfflineStore.shared.clear() }
        URLCache.shared.removeAllCachedResponses()
        Outbox.shared.clear()
    }

    /// The server deleted this account: forget everything on this phone too.
    func accountDeleted() { signOutLocally() }

    // MARK: Offline

    /// Sends the request; if there's no connection, queues `op` to replay later and applies it to the local copy.
    /// Returns nil when queued (the caller keeps its optimistic state).
    func runOrQueue<T: Sendable>(_ op: OutboxOp, _ request: @Sendable (APIClient) async throws -> T) async throws -> T? {
        do { return try await run(request) }
        catch let error as APIError where error.isOffline {
            Outbox.shared.enqueue(op)
            await OfflineStore.shared.apply(op)
            return nil
        }
    }

    /// Wires reconnect handling: probe the server while offline, and on reconnect send queued changes and refresh.
    func watchConnectivity() {
        Connectivity.shared.probe = { [weak self] in await self?.client?.ping() ?? false }
    }

    private func restore() async {
        defer { isRestoring = false }
        guard let client else { return }
        do { user = try await client.get("/me") }
        catch APIError.unauthorized { signOutLocally() }
        catch {
            // Server unreachable (or erroring): open with the account saved last time and carry on offline;
            // the connectivity probe brings it back. Only a never-synced install has to wait on the retry screen.
            if let url = client.url("/me"), let saved = await OfflineStore.shared.cached(for: url),
               let cached: User = try? client.decode(saved) {
                user = cached
                Connectivity.shared.setReachable(false)
            } else {
                user = nil
                offlineRestore = true
            }
        }
        watchConnectivity()
    }

    /// True when the token is kept but the server couldn't be reached at launch.
    private(set) var offlineRestore = false

    func retryRestore() async {
        isRestoring = true
        offlineRestore = false
        await restore()
    }
}
