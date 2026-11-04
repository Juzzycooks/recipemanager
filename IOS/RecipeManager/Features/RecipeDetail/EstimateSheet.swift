import SwiftUI

/// "How this was estimated": every ingredient line with what it counted for, so a surprising figure can be traced.
struct EstimateSheet: View {
    let estimate: NutritionFacts.Estimate
    var servings: Int?
    var yieldUnit: String?
    @Environment(\.dismiss) private var dismiss

    private var lines: [NutritionSummary.ExplainedLine] { NutritionSummary.explainedLines(estimate) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if let kcal = estimate.kcal {
                            Text("\(NutritionSummary.number(kcal)) kcal for the whole recipe")
                                .font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                            if let servings, servings >= 1 {
                                Text("About \(NutritionSummary.number(kcal / Double(servings))) kcal per \(NutritionSummary.singular(yieldUnit))")
                                    .font(.subheadline).foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        if let counted = NutritionSummary.countedLine(estimate) {
                            Text(counted).font(.subheadline).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text("Each ingredient is matched to a food and weighed. Lines like salt or water count as nothing; lines we couldn't read aren't counted, so the real figure may be higher.")
                }
                .listRowBackground(AppColors.card)

                Section("Ingredients") {
                    ForEach(lines) { line in row(line) }
                }
                .listRowBackground(AppColors.card)
            }
            .appBackground()
            .listStyle(.insetGrouped)
            .navigationTitle("How this was estimated").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Line and its reading on the left, the figure on the right; stacked at accessibility sizes. One VoiceOver element.
    private func row(_ line: NutritionSummary.ExplainedLine) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                lineText(line).frame(maxWidth: .infinity, alignment: .leading)
                figure(line).fixedSize()
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                lineText(line)
                figure(line)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: Size.tap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }

    private func lineText(_ line: NutritionSummary.ExplainedLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.text).font(AppTypography.reading).foregroundStyle(line.note == nil ? AppColors.textPrimary : AppColors.textSecondary)
            if let detail = line.detail {
                Text(detail).font(.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func figure(_ line: NutritionSummary.ExplainedLine) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(line.value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(AppColors.textPrimary)
            if let note = line.note {
                Text(note).font(.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
