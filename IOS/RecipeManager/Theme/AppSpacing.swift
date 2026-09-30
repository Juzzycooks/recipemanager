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

enum Radius {
    static let small: CGFloat = 10
    static let field: CGFloat = 14
    static let card: CGFloat = 16
    static let sheet: CGFloat = 28
}

enum Size {
    /// Minimum comfortable tap target.
    static let tap: CGFloat = 44
    static let addButton: CGFloat = 56
    static let avatar: CGFloat = 40
}
