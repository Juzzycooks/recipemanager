import CoreGraphics

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
    /// Side margin shared by every screen.
    static let screen: CGFloat = 20
}

/// Index-card corners, as on the web: 4pt on controls, fields, buttons and thumbnails, 6pt on cards.
/// Sheets keep the system shape.
enum Radius {
    static let control: CGFloat = 4
    static let small: CGFloat = control
    static let field: CGFloat = control
    static let card: CGFloat = 6
    static let sheet: CGFloat = 28
}

enum Size {
    /// Minimum comfortable tap target.
    static let tap: CGFloat = 44
    static let avatar: CGFloat = 40
}
