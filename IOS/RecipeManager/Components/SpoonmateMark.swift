import SwiftUI

/// The Spoonmate mark (a spoon whose bowl is a leaf), drawn with paths so it needs no image asset. Same geometry as the
/// app icon (tools/generate_icons.py): a pointed leaf with veins on a flared handle, tilted 28° clockwise.
struct SpoonmateMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            var c = context
            // Centre the drawing (its middle is about (0.5, 0.53) of the unit square), tilt it, then scale to fit.
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.rotate(by: .degrees(28))
            c.scaleBy(x: 1.0, y: 1.0)
            c.translateBy(x: -s * 0.5, y: -s * 0.53)

            let cx = 0.5, baseY = 0.60, length = 0.50, width = 0.40
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Handle: slim at the neck, flaring to a rounded end.
            let topY = 0.55, endY = 0.925, topR = 0.017, endR = 0.040
            var handle = Path()
            handle.move(to: p(cx - topR, topY)); handle.addLine(to: p(cx + topR, topY))
            handle.addLine(to: p(cx + endR, endY)); handle.addLine(to: p(cx - endR, endY)); handle.closeSubpath()
            handle.addEllipse(in: CGRect(x: (cx - endR) * s, y: (endY - endR) * s, width: endR * 2 * s, height: endR * 2 * s))
            // Solid, not outlined: outlining a path made of overlapping shapes draws seams through it.
            c.fill(handle, with: .color(AppColors.textSecondary.opacity(0.42)))

            // Leaf: two cubic curves meeting at a point.
            let tip = p(cx, baseY - length)
            let l1 = p(cx - width * 0.78, baseY - length * 0.04), l2 = p(cx - width * 0.56, baseY - length * 0.78)
            let r1 = p(cx + width * 0.78, baseY - length * 0.04), r2 = p(cx + width * 0.56, baseY - length * 0.78)
            var leaf = Path()
            leaf.move(to: p(cx, baseY))
            leaf.addCurve(to: tip, control1: l1, control2: l2)
            leaf.addCurve(to: p(cx, baseY), control1: r2, control2: r1)
            c.fill(leaf, with: .color(AppColors.secondary))

            // Veins (background colour, so they read as cut-outs), kept inside the leaf.
            func halfWidth(at t: Double) -> Double {
                // Sample the left edge and read its distance from the midrib at that height.
                let target = baseY - length * t
                var best = 0.0, bestGap = Double.infinity
                for i in 0...80 {
                    let u = Double(i) / 80, v = 1 - u
                    let x = v*v*v*cx + 3*v*v*u*(cx - width*0.78) + 3*v*u*u*(cx - width*0.56) + u*u*u*cx
                    let y = v*v*v*baseY + 3*v*v*u*(baseY - length*0.04) + 3*v*u*u*(baseY - length*0.78) + u*u*u*(baseY - length)
                    if abs(y - target) < bestGap { bestGap = abs(y - target); best = cx - x }
                }
                return best
            }
            var veins = Path()
            veins.move(to: p(cx, baseY - 0.012)); veins.addLine(to: p(cx, baseY - length * 0.80))
            let rise = 0.06
            for t in [0.26, 0.46, 0.64] {
                let y = baseY - length * t, reach = halfWidth(at: t + rise / length) * 0.62
                veins.move(to: p(cx, y)); veins.addLine(to: p(cx - reach, y - rise))
                veins.move(to: p(cx, y)); veins.addLine(to: p(cx + reach, y - rise))
            }
            c.stroke(veins, with: .color(AppColors.background), style: StrokeStyle(lineWidth: 0.014 * s, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
