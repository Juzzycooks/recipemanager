import SwiftUI
import UIKit

/// Full-screen, one step at a time, screen kept awake. `onFinished` fires on Done (logs "I made this").
struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: RecipeDetail
    let onFinished: () -> Void

    @State private var index = 0
    @State private var goingForward = true
    @Environment(CookTimer.self) private var timer
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var showingTimer = false
    @State private var showingIngredients = false

    private var steps: [RecipeDetail.NumberedStep] { recipe.numberedSteps }
    private var current: RecipeDetail.NumberedStep? { steps.indices.contains(index) ? steps[index] : nil }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if timer.isActive { TimerPill().padding(.top, Spacing.xs) }
            if let step = current {
                VerticalScroll {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        RecipeImage(path: recipe.imageUrl, title: recipe.title, id: recipe.id)
                            .frame(maxWidth: .infinity).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .accessibilityHidden(true)
                        Text(step.heading ?? "Step \(step.number)").font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(step.text).font(AppTypography.readingLarge).foregroundStyle(AppColors.textPrimary).lineSpacing(6)
                        let needed = recipe.ingredients(for: step)
                        if !needed.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("For this step").font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.secondary)
                                ForEach(Array(needed.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(AppTypography.reading).foregroundStyle(AppColors.textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.m)
                            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
                            .accessibilityElement(children: .combine)
                        }
                        if let minutes = CookTimer.detectMinutes(in: step.text), !timer.isActive {
                            Button { Task { await timer.start(minutes: minutes, title: recipe.title, detail: step.text) } } label: {
                                Label("Start \(minutes) min timer", systemImage: "timer")
                            }
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }   // the timer keeps running
        .sheet(isPresented: $showingTimer) {
            TimerSheet(recipeTitle: recipe.title, detail: current?.text ?? "", suggestion: current.flatMap { CookTimer.detectMinutes(in: $0.text) })
        }
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
                    Section(section.heading ?? "Ingredients") { ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in Text(line).font(AppTypography.reading) } }
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

/// The running timer as a pill: live countdown, tap the x to cancel (which also stops any ringing).
struct TimerPill: View {
    @Environment(CookTimer.self) private var timer

    var body: some View {
        if let start = timer.startDate, let fire = timer.fireDate {
            HStack(spacing: Spacing.xs) {
                Image(systemName: timer.finished ? "bell.fill" : "timer")
                if timer.finished {
                    Text("Time's up").font(.headline)
                } else {
                    Text(timerInterval: start...fire, countsDown: true).font(.headline.monospacedDigit())
                }
                Button { timer.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel(timer.finished ? "Stop timer" : "Cancel timer")
            }
            .foregroundStyle(AppColors.onPrimary)
            .padding(.horizontal, Spacing.m).frame(minHeight: 36)
            .background(timer.finished ? AppColors.danger : AppColors.primary, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(timer.finished ? "Timer finished" : "Timer running")
        }
    }
}

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CookTimer.self) private var timer
    let recipeTitle: String
    let detail: String
    let suggestion: Int?
    private let presets = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                if timer.isActive {
                    TimerPill()
                    SecondaryButton(title: timer.finished ? "Stop timer" : "Cancel timer") { timer.cancel() }
                } else {
                    if let suggestion {
                        PrimaryButton(title: "Start \(suggestion) min (from this step)", systemImage: "timer") { start(suggestion) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(presets, id: \.self) { minutes in
                            FilterChip(title: minutes >= 60 ? "\(minutes / 60) hr" : "\(minutes) min") { start(minutes) }
                        }
                    }
                    Text(Self.ringingExplanation).font(.footnote)
                        .foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                }
                if timer.permissionDenied {
                    Label("Alarms and notifications are off for this app, so the timer won't ring. Turn them on in Settings.", systemImage: "bell.slash")
                        .font(.footnote).foregroundStyle(AppColors.danger)
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
                } else if timer.isActive && !timer.isAlarm && !timer.finished {
                    Text(Self.fallbackExplanation)
                        .font(.footnote).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
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

    private func start(_ minutes: Int) {
        Task { await timer.start(minutes: minutes, title: recipeTitle, detail: detail) }
    }

    /// Only iOS 26.1+ has alarm timers; older versions get repeating notifications, so don't promise a ringer.
    private static var ringingExplanation: String {
        if #available(iOS 26.1, *) { return "Rings like the Clock app, even with the phone locked or on silent." }
        return "You'll get a repeating notification when time's up, even with the app closed."
    }

    private static var fallbackExplanation: String {
        if #available(iOS 26.1, *) {
            return "Alarms are turned off for this app, so you'll get notifications instead. Turn on Alarms in Settings for a ringing timer."
        }
        return "This version of iOS has no alarm timers, so you'll get a repeating notification instead."
    }
}
