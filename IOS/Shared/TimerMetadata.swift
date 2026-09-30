import AlarmKit

/// Shared by the app and the Live Activity extension: what a kitchen timer says about itself.
@available(iOS 26.1, *)
struct TimerMetadata: AlarmMetadata {
    let recipeTitle: String
    let detail: String
}
