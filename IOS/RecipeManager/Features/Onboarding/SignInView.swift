import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case server, username, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Sign in").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                    Text("Connect to your Recipe Manager server.").foregroundStyle(AppColors.textSecondary)
                }
                VStack(spacing: Spacing.s) {
                    field("Server", prompt: "recipes.example.com") {
                        TextField("Server", text: $server, prompt: Text("recipes.example.com"))
                            .textContentType(.URL).keyboardType(.URL).focused($focus, equals: .server)
                            .submitLabel(.next).onSubmit { focus = .username }
                    }
                    field("Username", prompt: "Username") {
                        TextField("Username", text: $username, prompt: Text("Username"))
                            .textContentType(.username).focused($focus, equals: .username)
                            .submitLabel(.next).onSubmit { focus = .password }
                    }
                    field("Password", prompt: "Password") {
                        SecureField("Password", text: $password, prompt: Text("Password"))
                            .textContentType(.password).focused($focus, equals: .password)
                            .submitLabel(.go).onSubmit(signIn)
                    }
                }
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(AppColors.danger).fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: "Sign In", isLoading: isWorking, action: signIn)
                    .disabled(server.isEmpty || username.isEmpty || password.isEmpty)
                    .opacity(server.isEmpty || username.isEmpty || password.isEmpty ? 0.5 : 1)
            }
            .screenPadding().padding(.top, Spacing.m).frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if server.isEmpty { server = session.lastServer } }
    }

    private func field<Content: View>(_ title: String, prompt: String, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(.horizontal, Spacing.m).frame(minHeight: 52)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
    }

    private func signIn() {
        guard !isWorking, !server.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        isWorking = true; error = nil
        Task {
            defer { isWorking = false }
            do { try await session.signIn(server: server, username: username.trimmingCharacters(in: .whitespaces), password: password) }
            catch { self.error = error.localizedDescription }
        }
    }
}
