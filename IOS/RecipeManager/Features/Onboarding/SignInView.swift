import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    /// Problems shown under the field they belong to; `error` is for anything that isn't about one field.
    @State private var serverProblem: String?
    @State private var credentialsProblem: String?
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case server, username, password }

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Sign in").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                    Text("Connect to your Spoonmate server.").foregroundStyle(AppColors.textSecondary)
                    Text("Spoonmate works with a server you run yourself, so your recipes stay yours.")
                        .font(.footnote).foregroundStyle(AppColors.textSecondary)
                    if let help = URL(string: "https://github.com/Juzzycooks/recipemanager#quick-start") {
                        Link("New here? See how to set one up", destination: help).font(.footnote.weight(.medium))
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    field("Server address", problem: serverProblem,
                          hint: serverProblem == nil ? "The address you open Spoonmate at in a browser." : nil) {
                        TextField("Server address", text: $server, prompt: Text("recipes.example.com"))
                            .textContentType(.URL).keyboardType(.URL).focused($focus, equals: .server)
                            .submitLabel(.next).onSubmit { checkServer(); focus = .username }
                    }
                    field("Username", problem: nil, hint: nil) {
                        TextField("Username", text: $username)
                            .textContentType(.username).focused($focus, equals: .username)
                            .submitLabel(.next).onSubmit { focus = .password }
                    }
                    field("Password", problem: credentialsProblem, hint: nil) {
                        SecureField("Password", text: $password)
                            .textContentType(.password).focused($focus, equals: .password)
                            .submitLabel(.go).onSubmit(signIn)
                    }
                }
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(AppColors.danger).fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: "Sign in", isLoading: isWorking, action: signIn)
                    .disabled(server.isEmpty || username.isEmpty || password.isEmpty)
                    .opacity(server.isEmpty || username.isEmpty || password.isEmpty ? 0.5 : 1)
            }
            .screenPadding().padding(.top, Spacing.m).frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if server.isEmpty { server = session.lastServer } }
        .onChange(of: focus) { old, _ in if old == .server { checkServer() } }
        .onChange(of: server) { serverProblem = nil }
        .onChange(of: username) { credentialsProblem = nil }
        .onChange(of: password) { credentialsProblem = nil }
    }

    /// A visible label above the field (the placeholder is only an example), with its problem or hint below.
    private func field<Content: View>(_ title: String, problem: String?, hint: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(AppColors.textPrimary).accessibilityHidden(true)
            content()
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, Spacing.m).frame(minHeight: 52)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.field).stroke(problem == nil ? Color.clear : AppColors.danger, lineWidth: 1))
                .accessibilityHint(problem ?? hint ?? "")
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hint {
                Text(hint).font(.footnote).foregroundStyle(AppColors.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkServer() {
        let text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        serverProblem = text.isEmpty || Session.normalise(server: text) != nil ? nil
            : "That doesn't look like an address. Enter it like recipes.example.com or 192.168.1.20:5000."
    }

    private func signIn() {
        guard !isWorking, !server.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        checkServer()
        guard serverProblem == nil else { focus = .server; return }
        isWorking = true; error = nil; credentialsProblem = nil
        Task {
            defer { isWorking = false }
            do { try await session.signIn(server: server, username: username.trimmingCharacters(in: .whitespaces), password: password) }
            catch let APIError.server(_, code, message) where code == "invalid_credentials" {
                credentialsProblem = "\(message) Check both and try again."
                focus = .password
            } catch APIError.invalidServer {
                serverProblem = "That doesn't look like an address. Enter it like recipes.example.com."
                focus = .server
            } catch let APIError.server(status, _, _) where status == 404 || status == 405 {
                serverProblem = "Something answered at that address, but it isn't a Spoonmate server. Check the address, including any port."
                focus = .server
            } catch APIError.decoding {
                serverProblem = "Something answered at that address, but it isn't a Spoonmate server, or it needs updating."
                focus = .server
            } catch let e as APIError where e.isOffline {
                error = "You're offline. Connect to the internet (or your home network) and try again."
            } catch APIError.network {
                serverProblem = "Couldn't reach that server. Check the address, and that the server is running and reachable from this phone."
                focus = .server
            } catch { self.error = error.localizedDescription }
        }
    }
}
