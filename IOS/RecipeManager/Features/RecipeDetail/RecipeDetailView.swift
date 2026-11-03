import SwiftUI

struct RecipeDetailView: View {
    private enum DetailTab: String, CaseIterable, Identifiable { case ingredients = "Ingredients", steps = "Steps", notes = "Notes"; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: RecipeDetailModel
    @State private var tab = DetailTab.ingredients
    @State private var picked: Set<String> = []
    @AppStorage(UnitSystem.storageKey) private var unitSetting = UnitSystem.original.rawValue
    /// Set from the Ingredients tab to flip just this recipe; otherwise the Settings choice applies.
    @State private var unitOverride: UnitSystem?
    private var units: UnitSystem { unitOverride ?? UnitSystem(rawValue: unitSetting) ?? .original }
    /// ½× / 1× / 2× / 3×, as on the web. Kept only while this recipe is open (the web doesn't save it either).
    @State private var scale: Double = 1
    /// An ingredient line as shown: scaled first, then converted (the web's order, `static/units.js` render()).
    private func shown(_ line: String) -> String { UnitConversion.convert(IngredientScaling.scale(line, by: scale), to: units) }
    @State private var showingCook = false
    @State private var showingEditor = false
    @State private var showingPlan = false
    @State private var confirmDelete = false
    @State private var newComment = ""
    @ScaledMetric(relativeTo: .title2) private var stepNumeralWidth: CGFloat = 24

    init(id: Int) { _model = State(initialValue: RecipeDetailModel(id: id)) }

    /// Siri's "Cook …" opens this page with `app.pendingCook` set: go straight into cook mode once the recipe is here.
    private func startCookingIfAsked() {
        // Only the page on top answers (an older copy of the same recipe can sit lower in a stack).
        guard app.pendingCook == model.id, model.recipe != nil, app.isShowing(recipe: model.id) else { return }
        app.pendingCook = nil
        showingCook = true
    }

    var body: some View {
        VerticalScroll {
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
        .bottomActionBar { if let recipe = model.recipe { startBar(recipe) } else { Spacer() } }
        .task(id: session.dataVersion) {
            await model.load(session)
            startCookingIfAsked()
        }
        .onChange(of: app.pendingCook) { startCookingIfAsked() }
        .refreshable { await model.load(session) }
        .fullScreenCover(isPresented: $showingCook) {
            if let recipe = model.recipe { CookingView(recipe: recipe, units: units, scale: scale, onFinished: { Task { await model.madeIt(session, app) } }, onRate: { score in Task { await model.rate(score, session) } }) }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { RecipeEditorView(mode: .edit(model.recipe!), onClose: { showingEditor = false }) { model.recipe = $0 } }
        }
        .sheet(isPresented: $showingPlan) {
            if let recipe = model.recipe { AddToPlanSheet(recipeId: recipe.id, title: recipe.title) { app.say("Added to your meal plan.") } }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await model.delete(session, app) { dismiss() } } }
        } message: { Text("You can undo for a few seconds afterwards.") }
        .errorAlert($model.error)
    }

    // MARK: Hero and sheet

    private func hero(_ r: RecipeDetail) -> some View {
        RecipeImage(path: r.imageUrl, title: r.title, id: r.id)
            .frame(maxWidth: .infinity).frame(height: heroHeight(hasPhoto: !r.imageUrl.isEmpty)).clipped()
            .accessibilityHidden(true)
    }

    /// The photo gives way as the text grows, so large Dynamic Type still reaches the ingredients quickly.
    /// A letter tile is a band, not a picture, so it stays short.
    private func heroHeight(hasPhoto: Bool) -> CGFloat {
        if typeSize.isAccessibilitySize { return hasPhoto ? 200 : 150 }
        if typeSize >= .xxLarge { return hasPhoto ? 280 : 180 }
        return hasPhoto ? 340 : 200
    }

    private var tabAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.2) }

    private func sheet(_ r: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                Text(r.title).font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                FavoriteButton(isFavorite: r.isFavorite, size: 24) { Task { await model.toggleFavorite(session) } }
            }
            // Title, then meta, then the lede; rating and tags follow quietly (the stars stay tappable,
            // with a VoiceOver hint instead of a permanent "tap a star" line).
            metaRow(r)
            if !r.description.isEmpty {
                Text(r.description).font(AppTypography.note).foregroundStyle(AppColors.textSecondary)
            }
            RatingView(rating: r.avgRating, count: r.ratingCount) { score in Task { await model.rate(score, session) } }
                .padding(.vertical, -Spacing.xs)   // the 44pt star targets need no extra air around them
                .accessibilityValue(r.myRating.map { "You rated it \($0)" } ?? "")
            if !r.categories.isEmpty {
                Text(r.categories.map(\.name).joined(separator: " · ")).font(.footnote.weight(.semibold)).foregroundStyle(AppColors.primary)
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
                Button { withAnimation(tabAnimation) { tab = t } } label: {
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
        .overlay(alignment: .bottom) { Rectangle().fill(AppColors.rule).frame(height: 1) }
    }

    // MARK: Tab content

    @ViewBuilder private func ingredients(_ r: RecipeDetail) -> some View {
        if r.ingredientSections.isEmpty {
            Text("No ingredients yet.").foregroundStyle(AppColors.textSecondary)
        } else {
            // Scale and units side by side, as on the web's section bar; stacked when they don't fit (large text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { scalePicker.fixedSize(); unitPicker }
                VStack(spacing: Spacing.xs) { scalePicker; unitPicker }
            }
        }
        ForEach(Array(r.ingredientSections.enumerated()), id: \.offset) { sectionIndex, section in
            VStack(alignment: .leading, spacing: 0) {
                if let heading = section.heading { listHeading(heading) }
                ForEach(Array(section.lines.enumerated()), id: \.offset) { lineIndex, line in
                    let key = "\(sectionIndex)-\(lineIndex)"
                    IngredientRow(text: shown(line), isChecked: picked.contains(key)) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
                            if picked.contains(key) { picked.remove(key) } else { picked.insert(key) }
                        }
                    }
                }
            }
        }
        if !r.ingredientSections.isEmpty {
            // Ticked means "I already have it", so only the unticked lines go on the list.
            let total = r.ingredientSections.reduce(0) { $0 + $1.lines.count }
            let toBuy = total - picked.count
            // Like the web's picker (static/js/shopping.js), the lines go on the list as scaled; units stay as written.
            SecondaryButton(title: picked.isEmpty ? "Add all to shopping list"
                                  : toBuy > 0 ? "Add \(toBuy) to shopping list" : "You have everything", systemImage: "cart.badge.plus") {
                guard toBuy > 0 else { return }
                let lines = r.ingredientSections.enumerated().flatMap { s, section in
                    section.lines.enumerated().compactMap { l, line in
                        picked.contains("\(s)-\(l)") ? nil : IngredientScaling.scale(line, by: scale)
                    }
                }
                Task { if await model.addToShopping(lines: lines, session, app) { picked = [] } }
            }
            .disabled(!picked.isEmpty && toBuy == 0)
        }
        if let n = r.nutrition { nutrition(n) }
    }

    private var scalePicker: some View {
        Picker("Scale", selection: $scale) {
            ForEach(IngredientScaling.factors, id: \.self) { factor in
                Text(IngredientScaling.title(factor)).accessibilityLabel(IngredientScaling.spokenTitle(factor)).tag(factor)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Scale recipe")
    }

    private var unitPicker: some View {
        Picker("Units", selection: Binding(get: { units }, set: { unitOverride = $0 })) {
            ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// The method as a ruled list: an italic terracotta numeral beside each step, a rule-blue line beneath.
    private func steps(_ r: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if r.steps.isEmpty { Text("No method yet.").foregroundStyle(AppColors.textSecondary) }
            ForEach(r.numberedSteps) { step in
                VStack(alignment: .leading, spacing: 0) {
                    if let heading = step.heading { listHeading(heading) }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text("\(step.number)").font(AppTypography.stepNumeral.monospacedDigit()).foregroundStyle(AppColors.primary)
                            .frame(minWidth: stepNumeralWidth, alignment: .leading).accessibilityHidden(true)
                        Text(UnitConversion.convert(step.text, to: units)).font(AppTypography.reading).foregroundStyle(AppColors.textPrimary)
                            .lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Spacing.s)
                    .overlay(alignment: .bottom) { RuledLine() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(step.number). \(UnitConversion.convert(step.text, to: units))")
                }
            }
        }
    }

    /// A section heading inside an ingredient or step list: italic, in the accent.
    private func listHeading(_ text: String) -> some View {
        Text(text).font(AppTypography.sectionHeading).foregroundStyle(AppColors.primary)
            .padding(.top, Spacing.m).padding(.bottom, Spacing.xxs)
            .accessibilityAddTraits(.isHeader)
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
        PrimaryButton(title: "Start cooking", systemImage: "flame") { showingCook = true }
            .disabled(r.steps.isEmpty).opacity(r.steps.isEmpty ? 0.5 : 1)
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
