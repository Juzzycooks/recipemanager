import SwiftUI
import UIKit

/// The cook-mode palette, the Kitchen Instrument Panel: a fixed chalkboard, the same in light and dark and under
/// every theme, so the stove always sees the same thing. Only cook mode reads these; the theme tint never appears here.
enum CookColors {
    static let bar = Color("CookBar")
    static let ground = Color("CookGround")
    static let surface = Color("CookSurface")
    static let raised = Color("CookRaised")
    static let text = Color("CookText")
    static let muted = Color("CookMuted")
    static let ember = Color("CookEmber")
    /// Fill for the one primary action (Next); white text on it.
    static let emberFill = Color("CookEmberFill")
}

/// Alegreya for what is read at the stove, scaled with Dynamic Type. Controls stay in San Francisco.
enum CookFonts {
    static let numeral = Font.custom("Alegreya-BoldItalic", size: 72, relativeTo: .largeTitle)
    static let step = Font.custom("Alegreya-Regular", size: 27, relativeTo: .title2)
    static let label = Font.custom("Alegreya-MediumItalic", size: 20, relativeTo: .headline)
    static let ingredient = Font.custom("Alegreya-Regular", size: 21, relativeTo: .title3)
    static let finish = Font.custom("Alegreya-BoldItalic", size: 34, relativeTo: .largeTitle)
}

/// Full-screen, one step at a time, screen kept awake. `onFinished` fires on Done (logs "I made this");
/// `onRate`, when given, lets the cook rate the recipe on the finish screen.
struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipe: RecipeDetail
    var units: UnitSystem = .original
    let onFinished: () -> Void
    var onRate: ((Int) -> Void)? = nil

    enum Page: Hashable { case ingredients, steps }

    @State private var page: Page = .steps
    @State private var index = 0
    @State private var goingForward = true
    /// Ticked ingredient lines ("section-line"), kept while cook mode is open.
    @State private var checked: Set<String> = []
    @State private var finished = false
    @State private var rating: Int?
    @Environment(CookTimer.self) private var timer
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var showingTimer = false
    @ScaledMetric(relativeTo: .title3) private var checkbox: CGFloat = 30
    @ScaledMetric(relativeTo: .title3) private var dashLift: CGFloat = 7

    private var steps: [RecipeDetail.NumberedStep] { recipe.numberedSteps }
    private var current: RecipeDetail.NumberedStep? { steps.indices.contains(index) ? steps[index] : nil }
    private var isLast: Bool { index >= steps.count - 1 }
    private var progress: Double { finished ? 1 : steps.isEmpty ? 0 : Double(index + 1) / Double(steps.count) }

    var body: some View {
        VStack(spacing: 0) {
            header
            pageTabs
            if timer.isActive { CookTimerStack { showingTimer = true } }
            ZStack {
                switch page {
                case .steps: stepsPage
                case .ingredients: ingredientsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            bottomBar
        }
        .background(CookColors.ground.ignoresSafeArea())
        .overlay { if finished { finishPanel.transition(.opacity) } }
        .foregroundStyle(CookColors.text)
        .tint(CookColors.ember)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        .sensoryFeedback(.impact(weight: .light), trigger: checked)
        .sensoryFeedback(.selection, trigger: rating)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }   // the timers keep running
        .sheet(isPresented: $showingTimer) {
            TimerSheet(recipeTitle: recipe.title,
                       defaultName: page == .steps ? current.map { "Step \($0.number)" } : nil,
                       suggestion: page == .steps ? current.flatMap { CookTimer.detectMinutes(in: $0.text) } : nil)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Rectangle().fill(CookColors.ember).frame(width: geo.size.width * progress)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
            }
            .frame(height: 4)
            .background(CookColors.raised)
            .accessibilityHidden(true)
            HStack(spacing: Spacing.s) {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark")
                        .font(.headline)
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 56)
                        .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close cook mode")
                Spacer(minLength: Spacing.xs)
                Text(steps.isEmpty ? recipe.title : "Step \(index + 1) of \(steps.count)")
                    .font(.headline.monospacedDigit()).foregroundStyle(CookColors.muted).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.xs)
                Button { showingTimer = true } label: {
                    Image(systemName: "timer").font(.title2.weight(.medium))
                        .frame(width: 56, height: 56)
                        .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Timers")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
        }
        .background(CookColors.bar.ignoresSafeArea(edges: .top))
    }

    private var pageTabs: some View {
        HStack(spacing: 0) {
            tab("Ingredients", .ingredients)
            tab("Steps", .steps)
        }
        .background(CookColors.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(CookColors.raised).frame(height: 1) }
    }

    private func tab(_ title: String, _ value: Page) -> some View {
        let selected = page == value
        return Button { page = value } label: {
            Text(title).font(.headline).foregroundStyle(selected ? CookColors.text : CookColors.muted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(alignment: .bottom) { Rectangle().fill(selected ? CookColors.ember : .clear).frame(height: 3) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Steps

    @ViewBuilder private var stepsPage: some View {
        if let step = current {
            VerticalScroll { stepContent(step) }
                .id(index)
                .transition(reduceMotion ? .opacity
                            : .asymmetric(insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                                          removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)))
                // A deliberate sideways swipe only: long, and mostly horizontal, so scrolling a long step or
                // brushing the screen with a floury hand doesn't skip a step.
                .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                    let width = value.translation.width, height = value.translation.height
                    guard abs(width) > 110, abs(width) > abs(height) * 2 else { return }
                    advance(width < 0 ? 1 : -1)
                })
        } else {
            VStack(spacing: Spacing.s) {
                Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(CookColors.muted)
                Text("No method yet").font(CookFonts.label)
                Text("Add steps to this recipe to cook from them here.").font(.body).foregroundStyle(CookColors.muted)
                    .multilineTextAlignment(.center)
            }
            .screenPadding()
        }
    }

    private func stepContent(_ step: RecipeDetail.NumberedStep) -> some View {
        let text = UnitConversion.convert(step.text, to: units)
        let section = step.section.map(Self.sectionLabel).flatMap { $0.isEmpty ? nil : $0 }
        return VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let section { Text(section).font(CookFonts.label).foregroundStyle(CookColors.muted) }
                Text("\(step.number)").font(CookFonts.numeral).foregroundStyle(CookColors.ember)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                Text(text).font(CookFonts.step).foregroundStyle(CookColors.text).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([section, "Step \(step.number) of \(steps.count)", text].compactMap { $0 }.joined(separator: ". "))
            .accessibilityHint("Swipe up or down to change step.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: advance(1)
                case .decrement: advance(-1)
                @unknown default: break
                }
            }

            let needed = recipe.ingredients(for: step)
            if !needed.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("For this step").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
                    ForEach(Array(needed.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Rectangle().fill(CookColors.ember).frame(width: 12, height: 2)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dashLift }
                            Text(UnitConversion.convert(line, to: units)).font(CookFonts.ingredient).foregroundStyle(CookColors.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.m)
                .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .combine)
            }

            let stepTimerName = "Step \(step.number)"
            if let minutes = CookTimer.detectMinutes(in: step.text), timer.canAddMore,
               !timer.timers.contains(where: { $0.name == stepTimerName }) {
                Button { Task { await timer.start(minutes: minutes, name: stepTimerName, recipeTitle: recipe.title) } } label: {
                    Label("Start \(TimerSheet.format(minutes)) timer", systemImage: "timer")
                        .font(.headline).foregroundStyle(CookColors.ember)
                        .padding(.horizontal, Spacing.l).frame(minHeight: 56)
                        .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Ragu:" → "Ragu". User headings are shown as written, apart from the trailing colon.
    private static func sectionLabel(_ heading: String) -> String {
        var label = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        while label.hasSuffix(":") { label.removeLast() }
        return label.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Ingredients

    private var ingredientsPage: some View {
        VerticalScroll {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recipe.ingredientSections.enumerated()), id: \.offset) { s, section in
                    if let heading = section.heading.map(Self.sectionLabel), !heading.isEmpty {
                        Text(heading).font(CookFonts.label).foregroundStyle(CookColors.ember)
                            .padding(.top, s == 0 ? 0 : Spacing.xl).padding(.bottom, Spacing.xs)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { i, line in
                        ingredientRow(key: "\(s)-\(i)", line: UnitConversion.convert(line, to: units))
                    }
                }
            }
            .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
        }
    }

    private func ingredientRow(key: String, line: String) -> some View {
        let isOn = checked.contains(key)
        return Button {
            if isOn { checked.remove(key) } else { checked.insert(key) }
        } label: {
            HStack(spacing: Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? CookColors.emberFill : .clear)
                        .strokeBorder(isOn ? CookColors.emberFill : CookColors.muted, lineWidth: 2)
                    if isOn { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white) }
                }
                .frame(width: checkbox, height: checkbox)
                Text(line).font(CookFonts.ingredient).foregroundStyle(isOn ? CookColors.muted : CookColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.s).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(CookColors.raised).frame(height: 1) }
        .accessibilityLabel(line)
        .accessibilityValue(isOn ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Spacing.s) {
            if page == .ingredients {
                Button { page = .steps } label: {
                    Label(index == 0 ? "Start cooking" : "Back to step \(index + 1)", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(CookBarButtonStyle(filled: true))
                .disabled(steps.isEmpty)
            } else {
                Button { advance(-1) } label: { Label("Previous", systemImage: "arrow.left") }
                    .buttonStyle(CookBarButtonStyle(filled: false))
                    .disabled(index == 0)
                    .accessibilityLabel("Previous step")
                Button { isLast ? finish() : advance(1) } label: {
                    Label(isLast ? "Done" : "Next", systemImage: isLast ? "checkmark" : "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(CookBarButtonStyle(filled: true))
                .disabled(steps.isEmpty)
                .accessibilityLabel(isLast ? "Finish cooking" : "Next step")
            }
        }
        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
        .background(CookColors.bar.ignoresSafeArea(edges: .bottom))
    }

    private func advance(_ delta: Int) {
        let next = index + delta
        guard steps.indices.contains(next) else { return }
        goingForward = delta > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) { index = next }
    }

    // MARK: Finish

    private func finish() {
        onFinished()
        rating = recipe.myRating
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { finished = true }
    }

    private var finishPanel: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.largeTitle).imageScale(.large).foregroundStyle(CookColors.ember)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text("Nice. Marked as made.").font(CookFonts.finish).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(recipe.title).font(CookFonts.label).foregroundStyle(CookColors.muted).multilineTextAlignment(.center)
            }
            if let onRate {
                VStack(spacing: Spacing.xxs) {
                    Text("How was it?").font(.headline).foregroundStyle(CookColors.muted)
                    HStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { score in
                            Button { rating = score; onRate(score) } label: {
                                Image(systemName: score <= (rating ?? 0) ? "star.fill" : "star")
                                    .font(.title).foregroundStyle(CookColors.ember)
                                    .frame(width: 56, height: 56).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(score) out of 5")
                            .accessibilityAddTraits(rating == score ? .isSelected : [])
                        }
                    }
                }
            }
            Spacer()
            Button { dismiss() } label: { Text("Close") }
                .buttonStyle(CookBarButtonStyle(filled: true))
            Button {
                index = 0; page = .steps
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { finished = false }
            } label: {
                Text("Start over from step 1").font(.headline).foregroundStyle(CookColors.ember)
                    .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screen).padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CookColors.ground.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

/// Big, thumb-sized cook-mode buttons: ember fill for the one primary action, raised chalk for the rest.
private struct CookBarButtonStyle: ButtonStyle {
    var filled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(filled ? Color.white : CookColors.text)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(filled ? CookColors.emberFill : CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
    }
}

/// "Next →": the arrow follows the word, as on the web.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) { configuration.title; configuration.icon }
    }
}

// MARK: Timers

/// Every running timer in cook mode, side by side under the tabs.
struct CookTimerStack: View {
    @Environment(CookTimer.self) private var timer
    var onOpen: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(timer.timers) { CookTimerPill(running: $0, onOpen: onOpen) }
            }
            .padding(.horizontal, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, Spacing.xs)
        .background(CookColors.bar)
    }
}

/// One named timer: live countdown, a 56pt x to cancel it (which also stops its ringing). Ember when it has rung.
struct CookTimerPill: View {
    @Environment(CookTimer.self) private var timer
    let running: CookTimer.Running
    var onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button { onOpen?() } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: running.finished ? "bell.fill" : "timer")
                    Text(running.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if running.finished {
                        Text("Time's up").font(.headline)
                    } else {
                        Text(timerInterval: running.startDate...running.fireDate, countsDown: true).font(.headline.monospacedDigit())
                    }
                }
                .padding(.leading, Spacing.m)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .disabled(onOpen == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint(onOpen == nil ? "" : "Opens timers.")
            Button { timer.cancel(running.id) } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 56, height: 56).contentShape(Rectangle())
            }
            .accessibilityLabel(running.finished ? "Stop \(running.name) timer" : "Cancel \(running.name) timer")
        }
        .buttonStyle(.plain)
        .foregroundStyle(running.finished ? Color.white : CookColors.text)
        .background(running.finished ? CookColors.emberFill : CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The app-wide pill outside cook mode: the timer that needs attention next, and how many more are running.
struct TimerPill: View {
    @Environment(CookTimer.self) private var timer

    var body: some View {
        if let soonest = timer.soonest {
            HStack(spacing: Spacing.xs) {
                Image(systemName: soonest.finished ? "bell.fill" : "timer")
                Text(soonest.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if soonest.finished {
                    Text("Time's up").font(.headline)
                } else {
                    Text(timerInterval: soonest.startDate...soonest.fireDate, countsDown: true).font(.headline.monospacedDigit())
                }
                if timer.timers.count > 1 {
                    Text("+\(timer.timers.count - 1)").font(.subheadline.weight(.semibold))
                        .accessibilityLabel("and \(timer.timers.count - 1) more")
                }
                Button { timer.cancel(soonest.id) } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: Size.tap, height: Size.tap)
                }
                .accessibilityLabel(soonest.finished ? "Stop \(soonest.name) timer" : "Cancel \(soonest.name) timer")
            }
            .foregroundStyle(AppColors.onPrimary)
            .padding(.leading, Spacing.m).padding(.trailing, Spacing.xxs).frame(minHeight: Size.tap)
            .background(soonest.finished ? AppColors.danger : AppColors.primaryFill, in: Capsule())
            .accessibilityElement(children: .contain)
        }
    }
}

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CookTimer.self) private var timer
    let recipeTitle: String
    /// "Step 3" when opened on a step; otherwise timers are called "Timer 2" and so on.
    let defaultName: String?
    let suggestion: Int?
    @State private var name = ""
    @State private var customMinutes = 5
    private let presets = [1, 3, 5, 10, 15, 20, 30, 60]

    private var fallbackName: String {
        if let defaultName, !timer.timers.contains(where: { $0.name == defaultName }) { return defaultName }
        return timer.nextDefaultName
    }

    var body: some View {
        NavigationStack {
            VerticalScroll {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if timer.isActive {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(timer.timers) { CookTimerPill(running: $0, onOpen: nil) }
                        }
                    }
                    if timer.canAddMore { newTimer } else {
                        Text("That's \(CookTimer.maxTimers) timers, the most at once. Cancel one to start another.")
                            .font(.body).foregroundStyle(CookColors.muted)
                    }
                    if timer.permissionDenied {
                        Label("Alarms and notifications are off for this app, so timers won't ring. Turn them on in Settings.", systemImage: "bell.slash")
                            .font(.footnote).foregroundStyle(CookColors.ember)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url).font(.headline).frame(minHeight: 56)
                        }
                    } else if timer.usesFallback {
                        Text(Self.fallbackExplanation).font(.footnote).foregroundStyle(CookColors.muted)
                    }
                }
                .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
            }
            .background(CookColors.ground)
            .navigationTitle("Timers").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CookColors.bar, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(CookColors.text)
        .tint(CookColors.ember)
        .preferredColorScheme(.dark)
        .presentationBackground(CookColors.ground)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var newTimer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Name").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
            TextField("Name", text: $name, prompt: Text(fallbackName).foregroundStyle(CookColors.muted))
                .font(.title3).textInputAutocapitalization(.sentences).submitLabel(.done)
                .padding(.horizontal, Spacing.m).frame(minHeight: 56)
                .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 4))
        }
        if let suggestion {
            Button { start(suggestion) } label: {
                Label("Start \(Self.format(suggestion)), from this step", systemImage: "timer")
            }
            .buttonStyle(CookBarButtonStyle(filled: true))
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Spacing.xs)], spacing: Spacing.xs) {
            ForEach(presets, id: \.self) { minutes in
                Button { start(minutes) } label: {
                    Text(Self.format(minutes)).font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(Self.format(minutes)) timer")
            }
        }
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Custom").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
            HStack(spacing: Spacing.xs) {
                stepButton("minus", "Less time") { customMinutes = max(1, customMinutes - (customMinutes > 10 ? 5 : 1)) }
                Text(Self.format(customMinutes)).font(.title3.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Custom time, \(Self.format(customMinutes))")
                stepButton("plus", "More time") { customMinutes = min(600, customMinutes + (customMinutes >= 10 ? 5 : 1)) }
                Button { start(customMinutes) } label: {
                    Text("Start").font(.headline).foregroundStyle(Color.white)
                        .padding(.horizontal, Spacing.l).frame(minHeight: 56)
                        .background(CookColors.emberFill, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(Self.format(customMinutes)) timer")
            }
        }
        Text(Self.ringingExplanation).font(.footnote).foregroundStyle(CookColors.muted)
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.headline)
                .frame(width: 56, height: 56)
                .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func start(_ minutes: Int) {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : name
        name = ""
        Task { await timer.start(minutes: minutes, name: label, recipeTitle: recipeTitle) }
    }

    /// 5 → "5 min", 60 → "1 hr", 90 → "1 hr 30 min".
    static func format(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
    }

    /// Only iOS 26.1+ has alarm timers; older versions get repeating notifications, so don't promise a ringer.
    private static var ringingExplanation: String {
        if #available(iOS 26.1, *) { return "Timers ring like the Clock app, even with the phone locked or on silent." }
        return "You'll get a repeating notification when time's up, even with the app closed."
    }

    private static var fallbackExplanation: String {
        if #available(iOS 26.1, *) {
            return "Alarms are turned off for this app, so you'll get notifications instead. Turn on Alarms in Settings for a ringing timer."
        }
        return "This version of iOS has no alarm timers, so you'll get a repeating notification instead."
    }
}
