import SwiftUI

/// A small waveform in the hands-free strip: moves gently while listening (still with Reduce Motion), a speaker while
/// reading aloud, a pause sign while interrupted.
struct ListeningIndicator: View {
    let phase: HandsFreeController.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(phase == .paused ? CookColors.muted : CookColors.ember)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: phase == .listening && !reduceMotion)
            .frame(width: 28, height: 44)
            .accessibilityHidden(true)   // the caption beside it says the same in words
    }

    private var symbol: String {
        switch phase {
        case .listening, .off: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .paused: "pause.circle"
        }
    }
}

/// What you can say, plus the read-aloud switch. Chalkboard like the rest of cook mode.
struct VoiceHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var readsStepsAloud: Bool

    private let commands: [(String, String)] = [
        ("“Next” or “Continue”", "Go to the next step."),
        ("“Back” or “Previous”", "Go to the step before."),
        ("“Repeat” or “What's the step?”", "Read the step aloud."),
        ("“Ingredients” or “What do I need?”", "Read this step's ingredients, or all of them."),
        ("“How much butter?”", "Read that ingredient's line, scaled."),
        ("“Set a timer for ten minutes”", "Start a timer. “Half an hour” and “an hour and a half” work too."),
        ("“Start the timer”", "Start the timer the step mentions."),
        ("“Stop listening”", "Turn hands-free off."),
    ]

    var body: some View {
        NavigationStack {
            VerticalScroll {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Toggle("Read each step aloud", isOn: $readsStepsAloud)
                        .font(.headline).frame(minHeight: 56)
                        .padding(.horizontal, Spacing.m)
                        .background(CookColors.surface, in: RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(commands, id: \.0) { phrase, effect in
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(phrase).font(CookFonts.label).foregroundStyle(CookColors.text)
                                Text(effect).font(.body).foregroundStyle(CookColors.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("Speak after a short pause, and say the command on its own. Your voice is recognised on this iPhone and never sent anywhere. Listening stops when you leave cook mode or switch apps.")
                        .font(.footnote).foregroundStyle(CookColors.muted)
                }
                .padding(.horizontal, Spacing.screen).padding(.vertical, Spacing.l)
            }
            .background(CookColors.ground)
            .navigationTitle("Hands-free").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CookColors.bar, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(CookColors.text)
        .tint(CookColors.ember)
        .preferredColorScheme(.dark)
        .presentationBackground(CookColors.ground)
        .presentationDetents([.medium, .large])
    }
}
