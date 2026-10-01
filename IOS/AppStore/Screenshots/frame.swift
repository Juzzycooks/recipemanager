// App Store screenshot framer for Spoonmate, adapted from the ShelfHead "navy" framer: a forest-green
// ground (the app icon palette), cream titles and sage subtitles, with a photographic iPhone frame from
// `assets/iphone-frame.png`
// and a layout that keeps the WHOLE phone on the canvas. Modes: single, and a two-slide crossover (pair).
//
//   single:  swift frame.swift single <in.png> <out.png> <W> <H> "<title>" "<subtitle>"
//   pair:    swift frame.swift pair <in.png> <outLeft.png> <outRight.png> <W> <H> \
//                  "<titleL>" "<subL>" "<titleR>" "<subR>"
//
// Pure AppKit/CoreGraphics; no dependencies. Run with DEVELOPER_DIR pointing at Xcode.
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let gradTop = rgb(0x2F6D4C), gradBottom = rgb(0x143023)
let titleColor = rgb(0xF6F1E4), subColor = rgb(0xCFE3B8)

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: see header\n", stderr); exit(2) }
let mode = args[1]

func loadShot(_ path: String) -> (NSImage, CGFloat, CGFloat) {
    guard let img = NSImage(contentsOfFile: path), let rep = img.representations.first else {
        fputs("cannot read \(path)\n", stderr); exit(1)
    }
    return (img, CGFloat(rep.pixelsWide), CGFloat(rep.pixelsHigh))
}

func makeCanvas(_ W: CGFloat, _ H: CGFloat) -> (NSBitmapImageRep, NSGraphicsContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    return (rep, ctx)
}

func drawGround(_ W: CGFloat, _ H: CGFloat) {
    NSGradient(colors: [gradTop, gradBottom])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
}

/// The device is a photographic iPhone frame lifted from the 5.4 originals
/// (`assets/iphone-frame.png`, produced by `assets/extract-frame.swift`), with the screen punched
/// out; the new screenshot is drawn into that hole and the frame composited on top. `screenW` is
/// the width of the HOLE in canvas pixels; `center` is the hole's centre; `degrees` rotates both.
struct FrameAsset {
    let image: NSImage
    let w: CGFloat, h: CGFloat
    let hole: NSRect          // AppKit coords (y-up) within the asset
    let bodyTop: CGFloat      // px above the hole's top edge to the body's top edge
    let bodyBottom: CGFloat   // px below the hole's bottom edge to the body's bottom edge
    let bodyLeft: CGFloat, bodyRight: CGFloat
    let radius: CGFloat
}
func loadFrame() -> FrameAsset {
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let png = dir.appendingPathComponent("assets/iphone-frame.png").path
    let json = dir.appendingPathComponent("assets/iphone-frame.json").path
    guard let img = NSImage(contentsOfFile: png), let rep = img.representations.first,
          let data = FileManager.default.contents(atPath: json),
          let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fputs("missing assets/iphone-frame.png(.json) next to the script\n", stderr); exit(1)
    }
    func f(_ k: String) -> CGFloat { CGFloat((m[k] as! NSNumber).doubleValue) }
    let W = CGFloat(rep.pixelsWide), H = CGFloat(rep.pixelsHigh)
    img.size = NSSize(width: W, height: H)
    let hole = NSRect(x: f("holeX"), y: H - f("holeY") - f("holeH"), width: f("holeW"), height: f("holeH"))
    return FrameAsset(image: img, w: W, h: H, hole: hole,
                      bodyTop: f("holeY") - f("bodyTop"), bodyBottom: f("bodyBottom") - (f("holeY") + f("holeH")),
                      bodyLeft: f("holeX") - f("bodyLeft"), bodyRight: f("bodyRight") - (f("holeX") + f("holeW")),
                      radius: f("r"))
}
let frame = loadFrame()

func drawDevice(_ shot: NSImage, shotW: CGFloat, shotH: CGFloat, screenW: CGFloat, center: CGPoint,
                degrees: CGFloat, bezelPad: CGFloat, ctx: NSGraphicsContext) {
    let cg = ctx.cgContext
    let k = screenW / frame.hole.width
    let holeW = screenW, holeH = frame.hole.height * k
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: degrees * .pi / 180)
    let holeRect = NSRect(x: -holeW / 2, y: -holeH / 2, width: holeW, height: holeH)
    // soft shadow under the body
    let body = NSRect(x: holeRect.minX - frame.bodyLeft * k, y: holeRect.minY - frame.bodyBottom * k,
                      width: holeW + (frame.bodyLeft + frame.bodyRight) * k,
                      height: holeH + (frame.bodyTop + frame.bodyBottom) * k)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -body.width * 0.03), blur: body.width * 0.10,
                 color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.black.withAlphaComponent(0.001).setFill()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.16, yRadius: body.width * 0.16).fill()
    cg.restoreGState()
    // screenshot into the hole (clipped to the hole's rounded shape; the frame covers the seam)
    cg.saveGState()
    NSBezierPath(roundedRect: holeRect, xRadius: frame.radius * k, yRadius: frame.radius * k).addClip()
    shot.draw(in: holeRect, from: NSRect(x: 0, y: 0, width: shot.size.width, height: shot.size.height),
              operation: .sourceOver, fraction: 1)
    cg.restoreGState()
    // frame on top, positioned so its hole lands on holeRect
    let frameRect = NSRect(x: holeRect.minX - frame.hole.minX * k, y: holeRect.minY - frame.hole.minY * k,
                           width: frame.w * k, height: frame.h * k)
    frame.image.draw(in: frameRect, from: NSRect(x: 0, y: 0, width: frame.w, height: frame.h),
                     operation: .sourceOver, fraction: 1)
    cg.restoreGState()
}

func captionAttrs(_ W: CGFloat, align: NSTextAlignment) -> ([NSAttributedString.Key: Any], [NSAttributedString.Key: Any]) {
    let para = NSMutableParagraphStyle(); para.alignment = align; para.lineBreakMode = .byWordWrapping
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: W * 0.072, weight: .bold), .foregroundColor: titleColor,
        .paragraphStyle: para, .kern: -1.0]
    let sub: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: W * 0.040, weight: .regular),
        .foregroundColor: subColor, .paragraphStyle: para]
    return (title, sub)
}

/// Draws title+subtitle with the top of the block at `topY` (AppKit coords); returns the block's bottom y.
@discardableResult
func drawCaption(_ title: String, _ sub: String, x: CGFloat, width: CGFloat, topY: CGFloat, W: CGFloat,
                 align: NSTextAlignment) -> CGFloat {
    let (ta, sa) = captionAttrs(W, align: align)
    let t = NSAttributedString(string: title, attributes: ta)
    let s = NSAttributedString(string: sub, attributes: sa)
    let tr = t.boundingRect(with: NSSize(width: width, height: 2000), options: [.usesLineFragmentOrigin])
    let sr = s.boundingRect(with: NSSize(width: width, height: 2000), options: [.usesLineFragmentOrigin])
    var y = topY - tr.height
    t.draw(with: NSRect(x: x, y: y, width: width, height: tr.height), options: [.usesLineFragmentOrigin])
    if !sub.isEmpty {
        y -= sr.height + W * 0.010
        s.draw(with: NSRect(x: x, y: y, width: width, height: sr.height), options: [.usesLineFragmentOrigin])
    }
    return y
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

switch mode {
case "single":
    guard args.count >= 8 else { fputs("single: in out W H title sub\n", stderr); exit(2) }
    let (shot, sw, sh) = loadShot(args[2])
    let out = args[3]
    let W = CGFloat(Double(args[4])!), H = CGFloat(Double(args[5])!)
    let (rep, ctx) = makeCanvas(W, H)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    drawGround(W, H)
    let margin = W * 0.06
    // Fixed two-line caption block so devices align across slides.
    let (ta, sa) = captionAttrs(W, align: .center)
    let twoLine = NSAttributedString(string: "Xg\nXg", attributes: ta)
        .boundingRect(with: NSSize(width: W - margin * 2, height: 2000), options: [.usesLineFragmentOrigin]).height
    let oneSub = NSAttributedString(string: "Xg", attributes: sa)
        .boundingRect(with: NSSize(width: W - margin * 2, height: 2000), options: [.usesLineFragmentOrigin]).height
    let topPad = H * 0.035
    drawCaption(args[6], args[7], x: margin, width: W - margin * 2, topY: H - topPad, W: W, align: .center)
    _ = twoLine; _ = oneSub
    // 6.1 (user feedback, 17 September 2026): the 5.5 set pinned the phone's top at 22.7% and let
    // the body run off the bottom of the canvas, which read as an incomplete phone. The whole
    // device now fits in the band between a fixed caption block (two-line title + two-line
    // subtitle, so devices still align across slides) and a bottom margin, capped at the old 72%
    // screen width so short captions don't produce a giant phone.
    let bezelPad = W * 0.022
    let captionBlockBottom = H - topPad - twoLine - W * 0.010 - oneSub * 2
    let bottomMargin = H * 0.045
    let bandTop = captionBlockBottom - H * 0.03
    let bodyUnitsH = frame.hole.height + frame.bodyTop + frame.bodyBottom
    let kFit = (bandTop - bottomMargin) / bodyUnitsH
    let k = min(kFit, (W * 0.72) / frame.hole.width)
    let screenW = frame.hole.width * k
    let holeH = frame.hole.height * k
    let bodyH = bodyUnitsH * k
    let bodyBottomY = bottomMargin + ((bandTop - bottomMargin) - bodyH) / 2   // centre in the band
    let holeBottomY = bodyBottomY + frame.bodyBottom * k
    drawDevice(shot, shotW: sw, shotH: sh, screenW: screenW,
               center: CGPoint(x: W / 2, y: holeBottomY + holeH / 2), degrees: 0, bezelPad: bezelPad, ctx: ctx)
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, out)

case "pair":
    guard args.count >= 11 else { fputs("pair: in outL outR W H titleL subL titleR subR\n", stderr); exit(2) }
    let (shot, sw, sh) = loadShot(args[2])
    let outL = args[3], outR = args[4]
    let W = CGFloat(Double(args[5])!), H = CGFloat(Double(args[6])!)
    let PW = W * 2
    let (rep, ctx) = makeCanvas(PW, H)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    drawGround(PW, H)
    // One large device, tilted, spanning the seam. Screen width ~1.05× a slide so it reads big and
    // bleeds off the top/bottom edges the way the reference set does.
    // Counter-clockwise tilt (screen text rises to the right, as in the reference set): the
    // phone's bottom-left corner moves right and down, leaving slide 1's bottom-left free for its
    // caption; the top-right corner moves up toward the seam, leaving slide 2's caption area clear.
    // Centre sits slightly left of the seam and below the middle so the top-right corner stays
    // clear of slide 2's centred caption.
    // Measured from the 5.4 originals: screen ≈1.2 slide-widths, ~30° CCW, centre well into slide 2
    // so slide 1 shows the phone's upper-left and slide 2 its lower-right, both bleeding off-canvas.
    // Tuned down from the 5.4 originals' 1.2x at the user's request ("B is way too enlarged"):
    // 0.92 slide-widths, 24° CCW, centre just right of the seam so slide 1 shows the upper-left
    // of the screen and slide 2 the lower half and right edge, both still bleeding off-canvas.
    // 6.1 (user feedback, 17 September 2026): the tilted phone used to bleed off the top and
    // bottom of both slides. It is now scaled so the whole rotated body fits vertically with a
    // margin, centred just right of the seam so slide 1 shows its upper-left and slide 2 its
    // lower-right — still one device across two slides, but a complete one, cut only at the seam.
    let bezelPad = W * 0.024
    let tilt: CGFloat = 24
    let rad = tilt * .pi / 180
    let bodyUnitsW = frame.hole.width + frame.bodyLeft + frame.bodyRight
    let bodyUnitsH = frame.hole.height + frame.bodyTop + frame.bodyBottom
    let rotatedUnitsH = bodyUnitsH * cos(rad) + bodyUnitsW * sin(rad)
    let kPair = (H * 0.90) / rotatedUnitsH
    let screenW = min(frame.hole.width * kPair, W * 0.92)
    drawDevice(shot, shotW: sw, shotH: sh, screenW: screenW,
               center: CGPoint(x: PW * 0.53, y: H * 0.50), degrees: tilt, bezelPad: bezelPad, ctx: ctx)
    // Left slide caption: bottom-left, left-aligned (the device occupies the upper right).
    let margin = W * 0.07
    let (ta, sa) = captionAttrs(W, align: .left)
    let tL = NSAttributedString(string: args[7], attributes: ta)
    let sL = NSAttributedString(string: args[8], attributes: sa)
    let capW = W * 0.58
    let trL = tL.boundingRect(with: NSSize(width: capW, height: 2000), options: [.usesLineFragmentOrigin])
    let srL = sL.boundingRect(with: NSSize(width: capW, height: 2000), options: [.usesLineFragmentOrigin])
    let bottomPad = H * 0.07
    sL.draw(with: NSRect(x: margin, y: bottomPad, width: capW, height: srL.height), options: [.usesLineFragmentOrigin])
    tL.draw(with: NSRect(x: margin, y: bottomPad + srL.height + W * 0.010, width: capW, height: trL.height),
            options: [.usesLineFragmentOrigin])
    // Right slide caption: top, centred within the right half.
    drawCaption(args[9], args[10], x: W + W * 0.40, width: W * 0.60 - margin, topY: H - H * 0.08, W: W, align: .right)
    NSGraphicsContext.restoreGraphicsState()
    // Split
    for (i, path) in [outL, outR].enumerated() {
        let (r2, c2) = makeCanvas(W, H)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = c2
        let whole = NSImage(size: NSSize(width: PW, height: H)); whole.addRepresentation(rep)
        whole.draw(in: NSRect(x: 0, y: 0, width: W, height: H),
                   from: NSRect(x: CGFloat(i) * W, y: 0, width: W, height: H), operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        writePNG(r2, path)
    }
default:
    fputs("unknown mode \(mode)\n", stderr); exit(2)
}
