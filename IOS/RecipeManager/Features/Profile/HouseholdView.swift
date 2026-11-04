import SwiftUI
import UIKit
import Observation

/// Your household: the people you share one shopping list with (API.md, "Households").
@MainActor @Observable
final class HouseholdModel {
    enum State: Equatable { case loading, none, member(Household), unsupported, failed(String) }

    var state: State = .loading
    var busy = false
    var error: String?

    var household: Household? {
        if case .member(let h) = state { return h }
        return nil
    }

    func load(_ session: Session) async {
        do {
            let response: HouseholdResponse = try await session.run { try await $0.get("/household") }
            state = response.household.map(State.member) ?? .none
        } catch let APIError.server(status, _, _) where status == 404 || status == 405 {
            state = .unsupported
        } catch {
            if household == nil { state = .failed(error.localizedDescription) }
        }
    }

    func create(_ session: Session, name: String) async {
        struct Body: Encodable, Sendable { let name: String }
        let body = Body(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        await change(session) { try await $0.send("POST", "/household", body: body) }
    }

    func join(_ session: Session, code: String) async {
        struct Body: Encodable, Sendable { let code: String }
        let body = Body(code: Household.normaliseCode(code))
        await change(session) { try await $0.send("POST", "/household/join", body: body) }
    }

    func leave(_ session: Session) async {
        await change(session) { try await $0.send("POST", "/household/leave") }
    }

    func newCode(_ session: Session) async {
        await change(session) { try await $0.send("POST", "/household/code") }
    }

    /// Every change answers with the household (or null). The shopping list is now a different list, so reload it.
    private func change(_ session: Session, _ request: @escaping @Sendable (APIClient) async throws -> HouseholdResponse) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let response = try await session.run(request)
            state = response.household.map(State.member) ?? .none
            session.recipesChanged()
        } catch {
            self.error = error.localizedDescription   // the server's own words: "That code doesn't match a household."
        }
    }
}

struct HouseholdView: View {
    @Environment(Session.self) private var session
    @State private var model = HouseholdModel()
    @State private var name = ""
    @State private var code = ""
    @State private var confirmLeave = false
    @State private var confirmNewCode = false
    @State private var copied = false

    var body: some View {
        List { content }
            .listStyle(.insetGrouped)
            .appBackground()
            .navigationTitle("Household").navigationBarTitleDisplayMode(.inline)
            .task { await model.load(session) }
            .refreshable { await model.load(session) }
            .errorAlert($model.error)
            .confirmationDialog("Leave this household?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { Task { await model.leave(session) } }
            } message: {
                Text(model.household?.isOwner == true && (model.household?.members.count ?? 0) > 1
                     ? "Your items leave with you. The member who joined first takes over the household."
                     : "Your items leave with you, and you'll have your own shopping list again.")
            }
            .confirmationDialog("Make a new invite code?", isPresented: $confirmNewCode, titleVisibility: .visible) {
                Button("New code") { Task { await model.newCode(session) } }
            } message: { Text("The old code stops working. People already in the household stay.") }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            Section { HStack { Spacer(); ProgressView(); Spacer() } }.listRowBackground(Color.clear)
        case .unsupported:
            Section {
                Text("This server doesn't support households yet. Update the server to share a shopping list.")
                    .foregroundStyle(AppColors.textSecondary)
            }
        case .failed(let message):
            Section {
                Text(message).foregroundStyle(AppColors.textSecondary)
                Button("Try again") { Task { await model.load(session) } }
            }
        case .none:
            Section {
                TextField("Household name", text: $name).textInputAutocapitalization(.words).submitLabel(.done)
                Button("Create household") { Task { await model.create(session, name: name); name = "" } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            } header: { Text("Start one") } footer: {
                Text("Share one shopping list with the people you live with. You'll get a code to invite them.")
            }
            Section {
                TextField("ABCD-EFGH", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Join") { Task { await model.join(session, code: code); if model.household != nil { code = "" } } }
                    .disabled(Household.normaliseCode(code).isEmpty || model.busy)
            } header: { Text("Join one") } footer: {
                Text("Enter the code someone in the household shared. Items already on your list join the shared one.")
            }
        case .member(let household):
            member(household)
        }
    }

    @ViewBuilder private func member(_ h: Household) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(h.name.isEmpty ? "Household" : h.name).font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                Text(h.members.count == 1 ? "Just you so far" : "\(h.members.count) people share the shopping list")
                    .font(.subheadline).foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, Spacing.xxs)
        }
        Section {
            ForEach(h.members) { m in
                HStack(spacing: Spacing.s) {
                    AvatarView(name: m.username, size: 32)
                    Text(m.username).foregroundStyle(AppColors.textPrimary)
                    if m.username == session.user?.username {
                        Text("You").font(.caption.weight(.semibold)).foregroundStyle(AppColors.primary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("Members") }
        if !h.inviteCode.isEmpty {
            Section {
                Text(h.inviteCode)
                    .font(.title2.monospaced().weight(.semibold)).foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityLabel("Invite code \(h.inviteCode.map(String.init).joined(separator: " "))")
                Button {
                    UIPasteboard.general.string = h.inviteCode
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                } label: { Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") }
                ShareLink(item: "Join my Spoonmate household with code \(h.inviteCode)") {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
                if h.isOwner {
                    Button { confirmNewCode = true } label: { Label("New code", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.busy)
                }
            } header: { Text("Invite code") } footer: {
                Text("Anyone with this code can join and see the shopping list.")
            }
        }
        Section {
            Button("Leave household", role: .destructive) { confirmLeave = true }
                .foregroundStyle(AppColors.danger).disabled(model.busy)
        }
    }
}
