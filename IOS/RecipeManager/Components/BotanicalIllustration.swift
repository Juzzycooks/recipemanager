import SwiftUI

/// A small hand-drawn-feeling sprig in a bowl, drawn with paths so the onboarding needs no image asset.
struct BotanicalIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let stroke = AppColors.secondary
            // Bowl
            var bowl = Path()
            bowl.move(to: CGPoint(x: w * 0.22, y: h * 0.72))
            bowl.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.72), control: CGPoint(x: w * 0.5, y: h * 0.72))
            bowl.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.96), control1: CGPoint(x: w * 0.78, y: h * 0.88), control2: CGPoint(x: w * 0.66, y: h * 0.96))
            bowl.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.72), control1: CGPoint(x: w * 0.34, y: h * 0.96), control2: CGPoint(x: w * 0.22, y: h * 0.88))
            context.fill(bowl, with: .color(AppColors.surface))
            context.stroke(bowl, with: .color(AppColors.textSecondary.opacity(0.5)), lineWidth: 1.5)
            // Stem
            var stem = Path()
            stem.move(to: CGPoint(x: w * 0.5, y: h * 0.74))
            stem.addCurve(to: CGPoint(x: w * 0.56, y: h * 0.12), control1: CGPoint(x: w * 0.44, y: h * 0.5), control2: CGPoint(x: w * 0.6, y: h * 0.32))
            context.stroke(stem, with: .color(stroke), lineWidth: 2)
            // Leaves: (position along stem 0…1, side, size)
            let leaves: [(t: CGFloat, side: CGFloat, scale: CGFloat)] =
                [(0.12, 1, 1.0), (0.2, -1, 1.05), (0.36, 1, 0.95), (0.46, -1, 1.0), (0.62, 1, 0.85), (0.72, -1, 0.85), (0.9, 1, 0.65), (1.0, 0, 0.7)]
            for leaf in leaves {
                let y = h * (0.74 - 0.62 * leaf.t)
                let x = w * (0.5 + 0.06 * leaf.t + (leaf.t < 0.5 ? -0.05 * sin(leaf.t * .pi) : 0.03))
                let length = w * 0.26 * leaf.scale
                let angle: CGFloat = leaf.side == 0 ? -90 : (leaf.side > 0 ? -35 : -145)
                var p = Path()
                p.move(to: .zero)
                p.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -length * 0.32))
                p.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: length * 0.32))
                let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle * .pi / 180)
                let placed = p.applying(transform)
                context.fill(placed, with: .color(stroke.opacity(0.85)))
                context.stroke(placed, with: .color(AppColors.primary.opacity(0.6)), lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}
