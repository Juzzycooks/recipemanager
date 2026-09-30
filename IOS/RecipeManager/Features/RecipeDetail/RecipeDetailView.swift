import SwiftUI

struct RecipeDetailView: View {
    private enum DetailTab: String, CaseIterable, Identifiable { case ingredients = "Ingredients", steps = "Steps", notes = "Notes"; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: RecipeDetailModel
    @State private var tab = DetailTab.ingredients
    @State private var picked: Set<String> = []
    @State private var showingCook = false
    @State private var showingEditor = false
    @State private var showingPlan = false
    @State private var confirmDelete = false
    @State private var newComment = ""

    init(id: Int) { _model = State(initialValue: RecipeDetailModel(id: id)) }

    var body: some View {
        ScrollView {
            if let recipe = model.recipe {
                VStack(spacing: 0) {
                    hero(recipe)
                    sheet(recipe).padding(.top, -Spacing.xl)
                }
            } else if model.error == nil {
                ProgressView().padding(.top, 120)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColors.background)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { if let recipe = model.recipe { toolbar(recipe) } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if let recipe = model.recipe { startBar(recipe) } }
        .hidesAppTabBar()
        .task(id: session.dataVersion) { await model.load(session) }
        .refreshable { await model.load(session) }
        .fullScreenCover(isPresented: $showingCook) {
            if let recipe = model.recipe { CookingView(recipe: recipe) { Task { await model.madeIt(session, app) } } }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { RecipeEditorView(mode: .edit(model.recipe!), onClose: { showingEditor = false }) { model.recipe = $0 } }
        }
        .sheet(isPresented: $showingPlan) {
            if let recipe = model.recipe { AddToPlanSheet(recipeId: recipe.id, title: recipe.title) { app.say("Added to your meal plan.") } }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await model.delete(session) { dismiss() } } }
        } message: { Text("You can undo for a few seconds afterwards.") }
        .errorAlert($model.error)
    }

    // MARK: Hero and sheet

    private func hero(_ r: RecipeDetail) -> some View {
        RecipeImage(path: r.imageUrl, title: r.title, id: r.id)
            .frame(maxWidth: .infinity).frame(height: 340).clipped()
            .accessibilityHidden(true)
    }

    private func sheet(_ r: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                Text(r.title).font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                FavoriteButton(isFavorite: r.isFavorite, size: 24) { Task { await model.toggleFavorite(session) } }
            }
            VStack(alignment: .leading, spacing: 2) {
                RatingView(rating: r.avgRating, count: r.ratingCount) { score in Task { await model.rate(score, session) } }
                if let mine = r.myRating {
                    Text("You rated it \(mine) star\(mine == 1 ? "" : "s")").font(.caption).foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("Tap a star to rate").font(.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
            metaRow(r)
            if !r.description.isEmpty {
                Text(r.description).font(AppTypography.reading).foregroundStyle(AppColors.textSecondary)
            }
            if !r.categories.isEmpty {
                Text(r.categories.map(\.name).joined(separator: " · ")).font(.footnote.weight(.medium)).foregroundStyle(AppColors.secondary)
            }
            tabs
            switch tab {
            case .ingredients: ingredients(r)
            case .steps: steps(r)
            case .notes: notes(r)
            }
        }
        .screenPadding().padding(.top, Spacing.l).padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background, in: UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet))
    }

    private func metaRow(_ r: RecipeDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.m) { metaItems(r) }
            VStack(alignment: .leading, spacing: Spacing.xxs) { metaItems(r) }
        }
    }

    @ViewBuilder private func metaItems(_ r: RecipeDetail) -> some View {
        if !r.prepTime.isEmpty { MetaItem(systemImage: "clock", text: "Prep \(r.prepTime)") }
        if !r.cookTime.isEmpty { MetaItem(systemImage: "flame", text: "Cook \(r.cookTime)") }
        if !r.servings.isEmpty { MetaItem(systemImage: "person.2", text: "\(r.servings) servings") }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { t in
                Button { withAnimation(.snappy(duration: 0.2)) { tab = t } } label: {
                    Text(t.rawValue).font(AppTypography.label)
                        .foregroundStyle(tab == t ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Size.tap)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(tab == t ? AppColors.primary : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppColors.separator).frame(height: 0.5) }
    }

    // MARK: Tab content

    @ViewBuilder private func ingredients(_ r: RecipeDetail) -> some View {
        if r.ingredientSections.isEmpty {
            Text("No ingredients yet.").foregroundStyle(AppColors.textSecondary)
        }
        ForEach(r.ingredientSections) { section in
            VStack(alignment: .leading, spacing: 0) {
                if let heading = section.heading {
                    Text(heading).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.secondary).padding(.top, Spacing.xs)
                }
                ForEach(section.lines, id: \.self) { line in
                    IngredientRow(text: line, isChecked: picked.contains(line)) {
                        withAnimation(.snappy(duration: 0.15)) { if picked.contains(line) { picked.remove(line) } else { picked.insert(line) } }
                    }
                }
            }
        }
        if !r.ingredientSections.isEmpty {
            SecondaryButton(title: picked.isEmpty ? "Add all to shopping list" : "Add \(picked.count) to shopping list", systemImage: "cart.badge.plus") {
                let lines = r.ingredientSections.flatMap(\.lines).filter { picked.contains($0) }
                Task { if await model.addToShopping(lines: lines, session, app) { picked = [] } }
            }
        }
        if let n = r.nutrition { nutrition(n) }
    }

    private func steps(_ r: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if r.steps.isEmpty { Text("No method yet.").foregroundStyle(AppColors.textSecondary) }
            ForEach(r.numberedSteps) { step in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let heading = step.heading {
                        Text(heading).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.secondary).padding(.top, Spacing.xs)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text("\(step.number)").font(.headline.monospacedDigit()).foregroundStyle(AppColors.onPrimary)
                            .frame(width: 28, height: 28).background(AppColors.primary, in: Circle()).accessibilityHidden(true)
                        Text(step.text).font(AppTypography.reading).foregroundStyle(AppColors.textPrimary).lineSpacing(3)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(step.number). \(step.text)")
                }
            }
        }
    }

    @ViewBuilder private func notes(_ r: RecipeDetail) -> some View {
        if !r.notes.isEmpty {
            Text(r.notes).font(AppTypography.reading).foregroundStyle(AppColors.textPrimary)
        } else {
            Text(r.canEdit ? "No notes yet. Add some from Edit." : "No notes.").foregroundStyle(AppColors.textSecondary)
        }
        HStack(spacing: Spacing.s) {
            Button { Task { await model.madeIt(session, app) } } label: { Label("I made this", systemImage: "checkmark.seal") }.buttonStyle(.bordered)
            if r.madeCount > 0 {
                Text("Made \(r.madeCount) time\(r.madeCount == 1 ? "" : "s")").font(.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
        if !r.sourceUrl.isEmpty, let url = URL(string: r.sourceUrl) {
            Link(destination: url) { Label("Original recipe", systemImage: "link") }.font(.subheadline)
        }
        Text("Comments").font(AppTypography.title3).padding(.top, Spacing.xs)
        ForEach(r.comments) { c in
            VStack(alignment: .leading, spacing: 2) {
                Text(c.text).foregroundStyle(AppColors.textPrimary)
                Text([c.user?.username, c.createdAt?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppColors.textSecondary)
            }
            .contextMenu { if c.canDelete { Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.deleteComment(c, session) } } } }
        }
        HStack {
            TextField("Add a comment", text: $newComment, axis: .vertical).padding(Spacing.s)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
            Button("Post") {
                let text = newComment
                Task { if await model.postComment(text, session) { newComment = "" } }
            }
            .fontWeight(.semibold).disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func nutrition(_ n: Nutrition) -> some View {
        let a = n.perServing
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Nutrition (estimate)").font(AppTypography.title3).padding(.top, Spacing.xs)
            HStack {
                stat("\(Int((a?.kcal ?? n.kcal).rounded()))", "kcal")
                stat(String(format: "%.0f", a?.protein ?? n.protein), "protein g")
                stat(String(format: "%.0f", a?.carbs ?? n.carbs), "carbs g")
                stat(String(format: "%.0f", a?.fat ?? n.fat), "fat g")
            }
            .padding(Spacing.s).background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
            Text("Rough figures \(a != nil ? "per serving" : "for the whole recipe"), from the ingredients we recognised.")
                .font(.caption).foregroundStyle(AppColors.textSecondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack { Text(value).font(.headline); Text(label).font(.caption2).foregroundStyle(AppColors.textSecondary) }
            .frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    // MARK: Chrome

    private func startBar(_ r: RecipeDetail) -> some View {
        PrimaryButton(title: "Start Cooking", systemImage: "flame") { showingCook = true }
            .disabled(r.steps.isEmpty).opacity(r.steps.isEmpty ? 0.5 : 1)
            .screenPadding().padding(.vertical, Spacing.s)
            .barBackground()
    }

    @ToolbarContentBuilder private func toolbar(_ r: RecipeDetail) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: shareText(r), subject: Text(r.title)) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Add to meal plan", systemImage: "calendar.badge.plus") { showingPlan = true }
                Button(r.shareUrl == nil ? "Create share link" : "Stop sharing", systemImage: "link") { Task { await model.toggleShare(session, app) } }
                if r.canEdit { Button("Edit", systemImage: "pencil") { showingEditor = true } }
                Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate(session, app) } }
                if r.canEdit { Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true } }
            } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("More")
        }
    }

    private func shareText(_ r: RecipeDetail) -> String {
        [r.title, r.shareUrl ?? (r.sourceUrl.isEmpty ? nil : r.sourceUrl)].compactMap { $0 }.joined(separator: "\n")
    }
}
