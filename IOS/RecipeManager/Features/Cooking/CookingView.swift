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

/// What the cook added on the finish panel: a note and a photo (JPEG), both optional.
struct CookFinish: Sendable, Equatable {
    var note = ""
    var photo: Data?
}

/// Full-screen, one step at a time, screen kept awake. After the last step the finish panel offers a photo and a note;
/// `onFinished` fires once, on Save or Skip (or on closing without either), and logs "I made this".
/// `onRate`, when given, lets the cook rate the recipe on the finish screen.
struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipe: RecipeDetail
    var units: UnitSystem = .original
    /// The recipe page's ½× / 1× / 2× / 3× choice; ingredient amounts are scaled, then converted. Method text isn't scaled (as on the web).
    var scale: Double = 1
    let onFinished: (CookFinish) -> Void
    var onRate: ((Int) -> Void)? = nil

    enum Page: Hashable { case ingredients, steps }

    @State private var page: Page = .steps
    @State private var index = 0
    @State private var goingForward = true
    /// Ticked ingredient lines ("section-line"), kept while cook mode is open.
    @State private var checked: Set<String> = []
    @State private var finished = false
    /// "I made this" has been sent for this finish (Save or Skip).
    @State private var logged = false
    @State private var finishNote = ""
    @State private var finishPhoto: Data?
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @FocusState private var noteFocused: Bool
    @State private var rating: Int?
    @Environment(CookTimer.self) private var timer
    @AppStorage("keepAwake") private var keepAwake = true
    @State private var showingTimer = false
    @Environment(\.scenePhase) private var scenePhase
    /// Hands-free voice control (off unless the cook turned it on; see HandsFreeController).
    @State private var handsFree = HandsFreeController()
    @State private var showingVoiceHelp = false
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
            if handsFree.isEnabled { handsFreeBar }
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
        .sensoryFeedback(.impact(weight: .medium), trigger: handsFree.commandCount)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            handsFree.onCommand = { perform($0) }
            handsFree.appear()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false   // the timers keep running
            handsFree.disappear()
            // Finished but closed without Save or Skip: it still counts as made (what Done always did).
            if finished && !logged { logged = true; onFinished(CookFinish()) }
        }
        .onChange(of: scenePhase) { handsFree.setForeground(scenePhase == .active) }
        .alert(item: $handsFree.notice) { notice in voiceAlert(notice) }
        .sheet(isPresented: $showingVoiceHelp) { VoiceHelpSheet(readsStepsAloud: $handsFree.readsStepsAloud) }
        .sheet(isPresented: $showingTimer) {
            TimerSheet(recipeTitle: recipe.title,
                       defaultName: page == .steps ? current.map { "Step \($0.number)" } : nil,
                       suggestion: page == .steps ? current.flatMap { StepDurations.find(in: $0.text).first } : nil)
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
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 56)
                        .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close cook mode")
                Spacer(minLength: Spacing.xs)
                Text(steps.isEmpty ? recipe.title : "Step \(index + 1) of \(steps.count)")
                    .font(.headline.monospacedDigit()).foregroundStyle(CookColors.muted).lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(-1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.xs)
                handsFreeToggle
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
        let lift = dashLift   // read here: the alignment closure below is Sendable
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

            let needed = recipe.ingredientMatch(for: step)
            if !needed.direct.isEmpty || !needed.earlier.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if !needed.direct.isEmpty {
                        Text("For this step").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
                        ingredientLines(needed.direct, lift: lift)
                    }
                    if !needed.earlier.isEmpty {
                        Text("From earlier").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
                            .padding(.top, needed.direct.isEmpty ? 0 : Spacing.s)
                        ingredientLines(needed.earlier, lift: lift)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.m)
                .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .combine)
            }

            // One button per time the step mentions ("Simmer 2–3 hours, then rest 10 minutes" gives two).
            let durations = StepDurations.find(in: step.text)
            ForEach(Array(durations.enumerated()), id: \.offset) { i, duration in
                let name = Self.timerName(step: step.number, index: i, duration: duration)
                if timer.canAddMore, !timer.timers.contains(where: { $0.name == name }) {
                    Button { Task { await timer.start(duration, name: name, recipeTitle: recipe.title) } } label: {
                        Label(Self.startTitle(duration), systemImage: "timer")
                            .font(.headline).foregroundStyle(CookColors.ember).multilineTextAlignment(.leading)
                            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.xs).frame(minHeight: 56)
                            .background(CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(duration.isRange ? "Starts at \(TimerSheet.format(seconds: duration.seconds)). When it rings you can add \(duration.extraMinutes) minutes." : "")
                }
            }
        }
        .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ingredient lines with the ember dash, as "For this step" and "From earlier" show them.
    private func ingredientLines(_ lines: [String], lift: CGFloat) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Rectangle().fill(CookColors.ember).frame(width: 12, height: 2)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + lift }
                Text(shown(line)).font(CookFonts.ingredient).foregroundStyle(CookColors.text)
            }
        }
    }

    /// "Step 3" for a step's first time, "Step 3 · 10 min" for the others, so each gets its own timer.
    static func timerName(step: Int, index: Int, duration: StepDuration) -> String {
        index == 0 ? "Step \(step)" : "Step \(step) · \(TimerSheet.format(seconds: duration.seconds))"
    }

    /// "Start 25 min timer", "Start 2 hr timer (up to 3 hr)", "Start timer: Overnight · about 8 hr".
    static func startTitle(_ duration: StepDuration) -> String {
        if duration.approx { return "Start timer: \(duration.label)" }
        if duration.isRange {
            return "Start \(TimerSheet.format(seconds: duration.seconds)) timer (up to \(TimerSheet.format(seconds: duration.maxSeconds)))"
        }
        return "Start \(TimerSheet.format(seconds: duration.seconds)) timer"
    }

    /// "Ragu:" → "Ragu". User headings are shown as written, apart from the trailing colon.
    private static func sectionLabel(_ heading: String) -> String {
        var label = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        while label.hasSuffix(":") { label.removeLast() }
        return label.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Ingredients

    private func shown(_ line: String) -> String { UnitConversion.convert(IngredientScaling.scale(line, by: scale), to: units) }

    private var ingredientsPage: some View {
        VerticalScroll {
            LazyVStack(alignment: .leading, spacing: 0) {
                if scale != 1 {
                    // Says why the amounts differ from the recipe as written (the scale is chosen on the recipe page).
                    Text("Amounts \(IngredientScaling.title(scale))").font(.subheadline.weight(.semibold)).foregroundStyle(CookColors.muted)
                        .padding(.bottom, Spacing.m)
                        .accessibilityLabel("Amounts scaled: \(IngredientScaling.spokenTitle(scale))")
                }
                ForEach(Array(recipe.ingredientSections.enumerated()), id: \.offset) { s, section in
                    if let heading = section.heading.map(Self.sectionLabel), !heading.isEmpty {
                        Text(heading).font(CookFonts.label).foregroundStyle(CookColors.ember)
                            .padding(.top, s == 0 ? 0 : Spacing.xl).padding(.bottom, Spacing.xs)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { i, line in
                        ingredientRow(key: "\(s)-\(i)", line: shown(line))
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
        if handsFree.readsStepsAloud { handsFree.say(spokenStep(next)) }   // only speaks while hands-free is listening
    }

    // MARK: Hands-free

    private var handsFreeToggle: some View {
        let on = handsFree.isEnabled
        return Button { toggleHandsFree() } label: {
            Image(systemName: on ? "mic.fill" : "mic.slash").font(.title2.weight(.medium))
                .foregroundStyle(on ? Color.white : CookColors.text)
                .frame(width: 56, height: 56)
                .background(on ? CookColors.emberFill : CookColors.raised, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Hands-free")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityHint(on ? "Stops listening for voice commands." : "Listens for voice commands such as next step.")
        .accessibilityAddTraits(.isToggle)
    }

    private func toggleHandsFree() {
        if handsFree.isEnabled {
            Task { await handsFree.setEnabled(false) }
        } else if UIAccessibility.isVoiceOverRunning {
            handsFree.notice = .voiceOverWarning     // explain, then let them turn it on anyway
        } else {
            Task { await handsFree.setEnabled(true) }
        }
    }

    /// The strip under the tabs while hands-free is on: what it's doing, the last command heard, read-aloud and help.
    private var handsFreeBar: some View {
        HStack(spacing: Spacing.xs) {
            ListeningIndicator(phase: handsFree.phase)
            Text(handsFree.caption ?? phaseText).font(.subheadline.weight(handsFree.caption == nil ? .regular : .semibold))
                .foregroundStyle(handsFree.caption == nil ? CookColors.muted : CookColors.ember)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            Button { handsFree.readsStepsAloud.toggle() } label: {
                Image(systemName: handsFree.readsStepsAloud ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.headline).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Read steps aloud")
            .accessibilityValue(handsFree.readsStepsAloud ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            Button { showingVoiceHelp = true } label: {
                Image(systemName: "questionmark.circle").font(.headline).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("What you can say")
        }
        .buttonStyle(.plain)
        .foregroundStyle(CookColors.text)
        .padding(.leading, Spacing.m).padding(.trailing, Spacing.xs)
        .background(CookColors.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(CookColors.raised).frame(height: 1) }
        .onChange(of: handsFree.caption) {
            if let caption = handsFree.caption { UIAccessibility.post(notification: .announcement, argument: caption) }
        }
    }

    private var phaseText: String {
        switch handsFree.phase {
        case .listening: "Listening. Say “next” or “repeat”."
        case .speaking: "Reading aloud"
        case .paused: "Paused"
        case .off: "Starting…"
        }
    }

    private func voiceAlert(_ notice: HandsFreeController.Notice) -> Alert {
        switch notice {
        case .denied:
            return Alert(title: Text("Hands-free needs the microphone"),
                         message: Text("Turn on Microphone and Speech Recognition for Spoonmate in Settings. Your voice is recognised on this iPhone and never leaves it."),
                         primaryButton: .default(Text("Open Settings")) {
                             if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                         },
                         secondaryButton: .cancel(Text("Not now")))
        case .unsupported:
            return Alert(title: Text("Hands-free isn't available on this iPhone"),
                         message: Text("It needs speech recognition that runs on the phone itself, which this iPhone or its language doesn't offer. Spoonmate won't send your voice to a server instead."),
                         dismissButton: .default(Text("OK")))
        case .couldNotStart:
            return Alert(title: Text("Couldn't start listening"),
                         message: Text("The microphone may be in use by another app or a call. Try hands-free again in a moment."),
                         dismissButton: .default(Text("OK")))
        case .voiceOverWarning:
            return Alert(title: Text("VoiceOver is on"),
                         message: Text("Hands-free listens while VoiceOver talks, so the two can talk over each other or VoiceOver may be heard as a command. You can still use both; headphones help."),
                         primaryButton: .default(Text("Turn on hands-free")) { Task { await handsFree.setEnabled(true) } },
                         secondaryButton: .cancel())
        }
    }

    private var spokenStep: String { spokenStep(index) }

    private func spokenStep(_ i: Int) -> String {
        guard steps.indices.contains(i) else { return "" }
        let step = steps[i]
        return "Step \(step.number). " + VoiceCommand.spoken(UnitConversion.convert(step.text, to: units))
    }

    private var allIngredientLines: [String] { recipe.ingredientSections.flatMap(\.lines).map(shown) }

    private func spokenList(_ lines: [String]) -> String {
        lines.map { VoiceCommand.spoken($0) }.joined(separator: ". ")
    }

    /// What each voice command does. Speaking goes through `handsFree.say`, which pauses listening meanwhile.
    private func perform(_ command: VoiceCommand) {
        switch command {
        case .next:
            if page != .steps { page = .steps; handsFree.say(spokenStep); return }
            if finished { handsFree.say(logged ? "You've finished. Tap Close when you're done." : "You've finished. Add a photo or note, or tap Skip."); return }
            if isLast { handsFree.say("That's the last step. Tap Done when you've finished."); return }
            advance(1)
        case .back:
            if page != .steps { page = .steps; handsFree.say(spokenStep); return }
            if index == 0 { handsFree.say("This is the first step."); return }
            advance(-1)
        case .repeatStep:
            handsFree.say(steps.isEmpty ? "This recipe has no method yet." : spokenStep)
        case .ingredients:
            let forStep = page == .steps ? current.map { recipe.ingredientMatch(for: $0) } : nil
            let direct = forStep?.direct.map(shown) ?? [], earlier = forStep?.earlier.map(shown) ?? []
            if !direct.isEmpty || !earlier.isEmpty {
                handsFree.say([direct.isEmpty ? nil : "For this step: " + spokenList(direct),
                               earlier.isEmpty ? nil : "From earlier: " + spokenList(earlier)].compactMap { $0 }.joined(separator: ". "))
            } else {
                let all = allIngredientLines
                handsFree.say(all.isEmpty ? "This recipe has no ingredients listed." : "You'll need: " + spokenList(all))
            }
        case .howMuch(let name):
            let found = VoiceCommand.lines(matching: name, in: allIngredientLines)
            handsFree.say(found.isEmpty ? "I couldn't find \(name) in the ingredients." : spokenList(found))
        case .setTimer(let seconds):
            startVoiceTimer(seconds: seconds, name: nil)
        case .startStepTimer:
            guard page == .steps, let step = current, let duration = StepDurations.find(in: step.text).first else {
                handsFree.say("This step doesn't mention a time. Say, set a timer for ten minutes.")
                return
            }
            let name = Self.timerName(step: step.number, index: 0, duration: duration)
            if timer.timers.contains(where: { $0.name == name }) { handsFree.say("The step \(step.number) timer is already running."); return }
            startVoiceTimer(seconds: duration.seconds, name: name, extraMinutes: duration.extraMinutes)
        case .stopListening:
            break   // handled by the controller
        }
    }

    private func startVoiceTimer(seconds: Int, name: String?, extraMinutes: Int = 0) {
        guard timer.canAddMore else {
            handsFree.say("That's \(CookTimer.maxTimers) timers already. Cancel one to start another.")
            return
        }
        let stepName = current.map { "Step \($0.number)" }
        let label = name ?? (stepName.flatMap { n in timer.timers.contains(where: { $0.name == n }) ? nil : n } ?? timer.nextDefaultName)
        let spoken = VoiceCommand.spokenDuration(seconds)
        Task {
            let started = await timer.start(seconds: seconds, name: label, recipeTitle: recipe.title, extraMinutes: extraMinutes)
            handsFree.say(started == nil ? "Couldn't start the timer." : "\(label) timer, \(spoken).")
        }
    }

    // MARK: Finish

    private func finish() {
        rating = recipe.myRating
        logged = false; finishNote = ""; finishPhoto = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { finished = true }
    }

    /// Save (with the photo and note) or Skip (just "made it"): either way the cook is logged once.
    private func logFinish(save: Bool) {
        guard !logged else { return }
        noteFocused = false
        logged = true
        onFinished(save ? CookFinish(note: finishNote.trimmingCharacters(in: .whitespacesAndNewlines), photo: finishPhoto) : CookFinish())
    }

    private var finishPanel: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                finishHeading
                if let onRate { ratingRow(onRate) }
                if logged { finishedActions } else { finishLog }
            }
            .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CookColors.ground.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .photoCapture(camera: $showingCamera, library: $showingLibrary) { finishPhoto = $0 }
    }

    private var finishHeading: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "checkmark.circle").font(.largeTitle).imageScale(.large).foregroundStyle(CookColors.ember)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text(logged ? "Nice. Marked as made." : "Nice. You made it.").font(CookFonts.finish).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(recipe.title).font(CookFonts.label).foregroundStyle(CookColors.muted).multilineTextAlignment(.center)
            }
        }
        .padding(.top, Spacing.l)
    }

    /// A photo and a note for your cook history, then Save or Skip.
    private var finishLog: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Add to your cook history").font(.headline).foregroundStyle(CookColors.muted)
            if let photo = finishPhoto, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        Button { finishPhoto = nil } label: {
                            Image(systemName: "xmark").font(.headline).foregroundStyle(CookColors.text)
                                .frame(width: 44, height: 44).background(CookColors.raised.opacity(0.9), in: Circle())
                                .frame(width: 56, height: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove photo")
                    }
                    .accessibilityLabel("Your photo")
            }
            HStack(spacing: Spacing.xs) {
                if PhotoCapture.hasCamera {
                    Button { showingCamera = true } label: { Label(finishPhoto == nil ? "Take photo" : "Retake", systemImage: "camera") }
                        .buttonStyle(CookBarButtonStyle(filled: false))
                }
                Button { showingLibrary = true } label: { Label(finishPhoto == nil ? "Choose photo" : "Choose another", systemImage: "photo") }
                    .buttonStyle(CookBarButtonStyle(filled: false))
            }
            TextField("Note (optional)", text: $finishNote, prompt: Text("A note for next time (optional)").foregroundStyle(CookColors.muted),
                      axis: .vertical)
                .lineLimit(2...5).font(.title3).focused($noteFocused)
                .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s).frame(minHeight: 56)
                .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Note")
            Button { logFinish(save: true) } label: { Text("Save") }
                .buttonStyle(CookBarButtonStyle(filled: true))
            Button { logFinish(save: false) } label: {
                Text("Skip").font(.headline).foregroundStyle(CookColors.ember)
                    .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Marks it as made without a photo or note")
        }
    }

    private func ratingRow(_ onRate: @escaping (Int) -> Void) -> some View {
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

    private var finishedActions: some View {
        VStack(spacing: Spacing.s) {
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
        .padding(.top, Spacing.l)
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
            if running.finished, running.extraMinutes > 0 {
                // A range ("2–3 hours") started at its low end: run the rest.
                Button { Task { await timer.extend(running.id) } } label: {
                    Text("+\(running.extraMinutes) min").font(.headline.monospacedDigit())
                        .padding(.horizontal, Spacing.s).frame(minHeight: 56).contentShape(Rectangle())
                }
                .accessibilityLabel("Add \(running.extraMinutes) minutes to \(running.name)")
            }
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
                if soonest.finished, soonest.extraMinutes > 0 {
                    Button("+\(soonest.extraMinutes) min") { Task { await timer.extend(soonest.id) } }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: Size.tap)
                        .accessibilityLabel("Add \(soonest.extraMinutes) minutes to \(soonest.name)")
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
    let suggestion: StepDuration?
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
            Button {
                let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : name
                name = ""
                Task { await timer.start(suggestion, name: label, recipeTitle: recipeTitle) }
            } label: {
                Label(suggestion.approx ? "Start \(suggestion.label), from this step" : "Start \(Self.format(seconds: suggestion.seconds)), from this step",
                      systemImage: "timer")
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
    nonisolated static func format(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
    }

    /// 45 → "45 sec", 90 → "1 min 30 sec", 600 → "10 min", 5400 → "1 hr 30 min" (whole minutes from an hour up).
    nonisolated static func format(seconds: Int) -> String {
        if seconds < 60 { return "\(max(0, seconds)) sec" }
        if seconds % 60 == 0 { return format(seconds / 60) }
        if seconds < 3600 { return "\(seconds / 60) min \(seconds % 60) sec" }
        return format(Int((Double(seconds) / 60).rounded()))
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
