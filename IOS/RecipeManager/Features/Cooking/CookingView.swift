import SwiftUI
import UIKit

/// Full-screen, one step at a time, screen kept awake. `onFinished` fires on Done (logs "I made this").
struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: RecipeDetail
    let onFinished: () -> Void

    @State private var index = 0
    @State private var goingForward = true
    @State private var timer = CookTimer()
    @State private var showingTimer = false
    @State private var showingIngredients = false

    private var steps: [RecipeDetail.NumberedStep] { recipe.numberedSteps }
    private var current: RecipeDetail.NumberedStep? { steps.indices.contains(index) ? steps[index] : nil }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if timer.isRunning || timer.finished { timerPill.padding(.top, Spacing.xs) }
            if let step = current {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        RecipeImage(path: recipe.imageUrl, title: recipe.title, id: recipe.id)
                            .frame(maxWidth: .infinity).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .accessibilityHidden(true)
                        Text(step.heading ?? "Step \(step.number)").font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(step.text).font(AppTypography.readingLarge).foregroundStyle(AppColors.textPrimary).lineSpacing(6)
                        if let minutes = CookTimer.detectMinutes(in: step.text), !timer.isRunning {
                            Button { timer.start(minutes: minutes) } label: { Label("Start \(minutes) min timer", systemImage: "timer") }
                                .buttonStyle(.bordered)
                        }
                    }
                    .screenPadding().padding(.top, Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)))
                .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                    if value.translation.width < -60 { advance(1) } else if value.translation.width > 60 { advance(-1) }
                })
            } else {
                EmptyStateView(title: "No method yet", systemImage: "text.alignleft", message: "Add steps to this recipe to cook from them here.")
            }
            controls
        }
        .clipped()
        .background(AppColors.background.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; timer.cancel() }
        .sheet(isPresented: $showingTimer) { TimerSheet(timer: timer, suggestion: current.flatMap { CookTimer.detectMinutes(in: $0.text) }) }
        .sheet(isPresented: $showingIngredients) { ingredientsSheet }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }.foregroundStyle(AppColors.textPrimary).frame(minWidth: 60, minHeight: Size.tap, alignment: .leading)
            Spacer()
            Text(steps.isEmpty ? recipe.title : "Step \(index + 1) of \(steps.count)").font(.headline).foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            HStack(spacing: 0) {
                Button { showingTimer = true } label: { Image(systemName: "timer").frame(width: Size.tap, height: Size.tap) }
                    .accessibilityLabel("Timer")
                Menu {
                    Button("Ingredients", systemImage: "list.bullet") { showingIngredients = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: Size.tap, height: Size.tap) }
                    .accessibilityLabel("More")
            }
            .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, Spacing.m)
    }

    private var timerPill: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: timer.finished ? "bell.fill" : "timer")
            Text(timer.finished ? "Time's up" : timer.display).font(.headline.monospacedDigit())
            Button { timer.cancel() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Cancel timer")
        }
        .foregroundStyle(AppColors.onPrimary)
        .padding(.horizontal, Spacing.m).frame(minHeight: 36)
        .background(timer.finished ? AppColors.danger : AppColors.primary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(timer.finished ? "Timer finished" : "Timer \(timer.display) remaining")
    }

    private var controls: some View {
        HStack {
            Button { advance(-1) } label: {
                Image(systemName: "arrow.left").font(.title2.weight(.medium)).foregroundStyle(AppColors.textPrimary)
                    .frame(width: 68, height: 68).background(AppColors.card, in: Circle())
                    .overlay(Circle().stroke(AppColors.separator))
            }
            .disabled(index == 0).opacity(index == 0 ? 0.35 : 1).accessibilityLabel("Previous step")
            Spacer()
            Button {
                if isLast { onFinished(); dismiss() } else { advance(1) }
            } label: {
                Image(systemName: isLast ? "checkmark" : "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(AppColors.onPrimary)
                    .frame(width: 68, height: 68).background(AppColors.primary, in: Circle())
            }
            .disabled(steps.isEmpty).accessibilityLabel(isLast ? "Finish cooking" : "Next step")
        }
        .buttonStyle(.plain)
        .screenPadding().padding(.vertical, Spacing.m)
    }

    private var ingredientsSheet: some View {
        NavigationStack {
            List {
                ForEach(recipe.ingredientSections) { section in
                    Section(section.heading ?? "Ingredients") { ForEach(section.lines, id: \.self) { Text($0).font(AppTypography.reading) } }
                }
            }
            .appBackground().navigationTitle("Ingredients").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingIngredients = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func advance(_ delta: Int) {
        let next = index + delta
        guard steps.indices.contains(next) else { return }
        goingForward = delta > 0
        withAnimation(.snappy(duration: 0.3)) { index = next }
    }
}

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let timer: CookTimer
    let suggestion: Int?
    private let presets = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                if timer.isRunning {
                    Text(timer.display).font(.system(size: 64, weight: .light, design: .serif).monospacedDigit()).foregroundStyle(AppColors.textPrimary)
                    SecondaryButton(title: "Cancel timer") { timer.cancel() }
                } else {
                    if let suggestion {
                        PrimaryButton(title: "Start \(suggestion) min (from this step)", systemImage: "timer") { timer.start(minutes: suggestion); dismiss() }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(presets, id: \.self) { minutes in
                            FilterChip(title: minutes >= 60 ? "\(minutes / 60) hr" : "\(minutes) min") { timer.start(minutes: minutes); dismiss() }
                        }
                    }
                }
                Spacer()
            }
            .screenPadding().padding(.top, Spacing.l)
            .background(AppColors.background)
            .navigationTitle("Timer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
