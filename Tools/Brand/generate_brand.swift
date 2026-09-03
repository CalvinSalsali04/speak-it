// Speak It brand generator.
//
// Draws the Speak It mark (five voice bars) and a custom monoline, geometric,
// all-caps wordmark — the lettering takes its cue from the HEYTEA wordmark:
// single-stroke letters, wide open tracking, softly rounded terminals — and
// exports every brand file the app, the website and the store listing use.
//
// Run:  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/Brand/generate_brand.swift
//
// Everything is drawn from geometry in this file, so there is no font to
// license or embed: the in-app wordmark is a PDF the asset catalog treats as a
// template image, and the SVGs are plain stroked paths.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

struct Point { var x: Double; var y: Double }

/// A glyph is a list of open polylines in a 100-unit cap-height space
/// (y grows downward, baseline at y = 100). Every line is a stroke centerline;
/// the stroke width is applied at draw time so the whole wordmark stays one
/// weight.
struct Glyph {
    var strokes: [[Point]]
    var advance: Double
}

let capHeight = 100.0
let strokeWidth = 16.0              // HEYTEA runs about 0.16–0.17 of cap height
let t = strokeWidth / 2             // centerline inset from the letter box
let tracking = 30.0                 // generous, like the reference
let wordSpace = 58.0

func arc(center: Point, radius: Double, from a0: Double, to a1: Double, steps: Int = 48) -> [Point] {
    (0...steps).map { i in
        let a = a0 + (a1 - a0) * Double(i) / Double(steps)
        let r = a * .pi / 180
        return Point(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
    }
}

func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

let glyphs: [Character: Glyph] = {
    var g: [Character: Glyph] = [:]

    // S — two tangent arcs, radius chosen so the circles kiss at mid-height.
    do {
        let r = (capHeight - 2 * t) / 4
        let cx = t + r
        let top = arc(center: p(cx, t + r), radius: r, from: -28, to: -270)
        let bottom = arc(center: p(cx, capHeight - t - r), radius: r, from: -90, to: 152)
        g["S"] = Glyph(strokes: [top + bottom.dropFirst()], advance: cx + r + t)
    }

    // P — stem plus a semicircular bowl.
    do {
        let bowlR = 22.0
        let bowlX = 38.0
        let bowl = [p(t, t), p(bowlX, t)]
            + arc(center: p(bowlX, t + bowlR), radius: bowlR, from: -90, to: 90).dropFirst()
            + [p(t, t + 2 * bowlR)]
        g["P"] = Glyph(strokes: [[p(t, t), p(t, capHeight - t)], Array(bowl)], advance: bowlX + bowlR + t)
    }

    // E — stem and three arms, the middle one a touch shorter.
    do {
        let w = 60.0
        g["E"] = Glyph(strokes: [
            [p(w - t, t), p(t, t), p(t, capHeight - t), p(w - t, capHeight - t)],
            [p(t, 50), p(w - t - 6, 50)],
        ], advance: w)
    }

    // A — pointed apex, crossbar sitting low enough to read at small sizes.
    do {
        let w = 84.0
        let apex = p(w / 2, t)
        let l = p(t, capHeight - t)
        let r = p(w - t, capHeight - t)
        let barY = 68.0
        let f = (barY - t) / (capHeight - 2 * t)
        let bl = p(l.x + (apex.x - l.x) * (1 - f), barY)
        let br = p(r.x + (apex.x - r.x) * (1 - f), barY)
        g["A"] = Glyph(strokes: [[l, apex, r], [bl, br]], advance: w)
    }

    // K — stem, upper arm, and a leg that leaves the arm rather than the stem.
    do {
        let w = 74.0
        let armTop = p(w - t - 2, t)
        let armRoot = p(t, 56)
        let f = 0.42
        let joint = p(armRoot.x + (armTop.x - armRoot.x) * f, armRoot.y + (armTop.y - armRoot.y) * f)
        g["K"] = Glyph(strokes: [
            [p(t, t), p(t, capHeight - t)],
            [armRoot, armTop],
            [joint, p(w - t, capHeight - t)],
        ], advance: w)
    }

    // I
    g["I"] = Glyph(strokes: [[p(t, t), p(t, capHeight - t)]], advance: strokeWidth)

    // T
    do {
        let w = 68.0
        g["T"] = Glyph(strokes: [[p(t, t), p(w - t, t)], [p(w / 2, t), p(w / 2, capHeight - t)]], advance: w)
    }

    g[" "] = Glyph(strokes: [], advance: wordSpace - tracking)
    return g
}()

/// Lays a string out and returns its strokes in wordmark space plus the total width.
func layout(_ text: String) -> (strokes: [[Point]], width: Double) {
    var x = 0.0
    var out: [[Point]] = []
    for (i, ch) in text.enumerated() {
        guard let glyph = glyphs[ch] else { fatalError("no glyph for \(ch)") }
        for s in glyph.strokes {
            out.append(s.map { p($0.x + x, $0.y) })
        }
        x += glyph.advance
        if i < text.count - 1 { x += tracking }
    }
    return (out, x)
}

// MARK: - Pen: a deterministic hand-drawn stroke tool

/// xorshift64* — a tiny seeded generator so every export is bit-identical.
struct Rand {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {          // uniform in [-1, 1]
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        let v = (state &* 0x2545F4914F6CDD1D) >> 11
        return Double(v) / Double(1 << 53) * 2 - 1
    }
}

/// Smooth 1-D value noise in [-1, 1]: `knots` random values, cosine-blended.
struct Noise1D {
    var knots: [Double]
    init(knots n: Int, rand: inout Rand) { knots = (0..<n).map { _ in rand.next() } }
    func value(at u: Double) -> Double {
        let x = min(max(u, 0), 1) * Double(knots.count - 1)
        let i = min(Int(x), knots.count - 2)
        let t = x - Double(i)
        let f = (1 - cos(t * .pi)) / 2
        return knots[i] * (1 - f) + knots[i + 1] * f
    }
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

/// A felt-tip pen. Give it an ideal centreline and it returns the closed ink
/// outline a hand would actually leave: the line drifts and trembles, the
/// width breathes with pressure, the edges are a little rough, the tip lands
/// heavy and lifts light, and neither end is a perfect semicircle.
/// Amplitudes are fractions of `width`.
struct Pen {
    var width: Double
    var seed: UInt64
    var drift = 0.09          // slow lateral wander of the whole line
    var tremor = 0.018        // faster hand shake
    var pressure = 0.09       // width variation along the stroke
    var roughness = 0.012      // edge noise, each side independent
    var landing = 0.06        // extra weight where the tip lands
    var lift = 0.10           // how much the stroke thins as the tip lifts
    var hook = 0.05           // sideways flick as the tip leaves the paper
    var samples = 64
    var capSamples = 14

    func outline(_ ideal: [Point]) -> [Point] {
        precondition(ideal.count >= 2)
        // Resample the ideal path by arc length.
        var cum = [0.0]
        for i in 1..<ideal.count {
            cum.append(cum[i - 1] + hypot(ideal[i].x - ideal[i - 1].x, ideal[i].y - ideal[i - 1].y))
        }
        let total = cum.last!
        // Texture is sized in pen widths, so a short flick and a long pull
        // get the same grain rather than the same number of wiggles.
        let widths = max(total / width, 0.5)
        var rand = Rand(seed: seed)
        let wander = Noise1D(knots: 2 + Int(widths * 0.6), rand: &rand)
        let shake = Noise1D(knots: 3 + Int(widths * 2.0), rand: &rand)
        let press = Noise1D(knots: 2 + Int(widths * 1.0), rand: &rand)
        let edgeL = Noise1D(knots: 4 + Int(widths * 3.0), rand: &rand)
        let edgeR = Noise1D(knots: 4 + Int(widths * 3.0), rand: &rand)
        let hookSign: Double = rand.next() < 0 ? -1 : 1
        let capSquashA = 0.86 + 0.14 * (rand.next() + 1) / 2
        let capSquashB = 0.86 + 0.14 * (rand.next() + 1) / 2
        let capNoiseA = Noise1D(knots: 7, rand: &rand)
        let capNoiseB = Noise1D(knots: 7, rand: &rand)
        // A short stroke has no room to wander.
        let reach = smoothstep(0.3, 3.0, widths)
        func at(_ d: Double) -> Point {
            var i = 1
            while i < cum.count - 1 && cum[i] < d { i += 1 }
            let a = ideal[i - 1], b = ideal[i]
            let seg = max(cum[i] - cum[i - 1], 1e-9)
            let t = min(max((d - cum[i - 1]) / seg, 0), 1)
            return p(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }

        // Centreline with the hand in it.
        var centre: [Point] = []
        var normals: [Point] = []
        for k in 0...samples {
            let u = Double(k) / Double(samples)
            let base = at(u * total)
            let ahead = at(min(u + 0.01, 1) * total), behind = at(max(u - 0.01, 0) * total)
            var tx = ahead.x - behind.x, ty = ahead.y - behind.y
            let tl = max(hypot(tx, ty), 1e-9); tx /= tl; ty /= tl
            let nx = -ty, ny = tx
            let side = drift * reach * width * wander.value(at: u)
                + tremor * reach * width * shake.value(at: u)
                + hook * reach * hookSign * width * pow(smoothstep(0.82, 1, u), 2)
            centre.append(p(base.x + nx * side, base.y + ny * side))
            normals.append(p(nx, ny))
        }
        // Recompute normals from the actual drawn line so the ink follows it.
        for k in 0...samples {
            let a = centre[max(k - 1, 0)], b = centre[min(k + 1, samples)]
            var tx = b.x - a.x, ty = b.y - a.y
            let tl = max(hypot(tx, ty), 1e-9); tx /= tl; ty /= tl
            normals[k] = p(-ty, tx)
        }

        // Half-widths on each side.
        var hl: [Double] = [], hr: [Double] = []
        for k in 0...samples {
            let u = Double(k) / Double(samples)
            var w = width * (1 + pressure * press.value(at: u))
            w *= 1 + landing * (1 - smoothstep(0, 0.18, u))
            w *= 1 - lift * smoothstep(0.72, 1, u)
            hl.append(w / 2 * (1 + roughness * edgeL.value(at: u)))
            hr.append(w / 2 * (1 + roughness * edgeR.value(at: u)))
        }

        // Assemble: left edge forward, tip cap, right edge back, landing cap.
        var out: [Point] = []
        for k in 0...samples { out.append(p(centre[k].x + normals[k].x * hl[k], centre[k].y + normals[k].y * hl[k])) }
        /// Sweeps from `c + n·r` through `c + along·r` to `c - n·r`.
        func cap(at c: Point, n: Point, along: Point, from ra: Double, to rb: Double, squash: Double, noise: Noise1D) -> [Point] {
            (1..<capSamples).map { j in
                let f = Double(j) / Double(capSamples)
                let a = f * .pi
                let r = (ra * (1 - f) + rb * f) * (1 + roughness * 1.5 * noise.value(at: f))
                let ahead = sin(a) * r * squash, across = cos(a) * r
                return p(c.x + n.x * across + along.x * ahead, c.y + n.y * across + along.y * ahead)
            }
        }
        let nEnd = normals[samples], tEnd = p(nEnd.y, -nEnd.x)          // forward tangent
        let nStart = normals[0], tStart = p(-nStart.y, nStart.x)        // backward tangent
        out += cap(at: centre[samples], n: nEnd, along: tEnd, from: hl[samples], to: hr[samples], squash: capSquashA, noise: capNoiseA)
        for k in stride(from: samples, through: 0, by: -1) { out.append(p(centre[k].x - normals[k].x * hr[k], centre[k].y - normals[k].y * hr[k])) }
        out += cap(at: centre[0], n: p(-nStart.x, -nStart.y), along: tStart, from: hr[0], to: hl[0], squash: capSquashB, noise: capNoiseB)
        return out
    }
}

// MARK: - The mark

/// Five voice bars. Heights are the ratios the existing mark has always used
/// (1 : 2.1 : 3.03) and the weight is the bar width, but each bar is inked by
/// `Pen` as one hand-drawn felt-tip stroke — the way HEYTEA's line drawing is
/// drawn — rather than a machined capsule. Everything is seeded, so every
/// export is identical.
struct Bars {
    var barWidth: Double
    var pitch: Double
    var heights: [Double]
    var width: Double { pitch * 4 + barWidth }
    var height: Double { heights.max()! }

    static func scaled(to height: Double) -> Bars {
        let unit = height / 2184
        return Bars(barWidth: 368 * unit, pitch: 600 * unit, heights: [720, 1512, 2184, 1512, 720].map { $0 * unit })
    }

    /// The hand: one entry per bar. `lean` tilts the stroke, `bow` curves it
    /// (both as fractions of the bar width), `stretch` nudges the length,
    /// `lift` shifts it up or down, `seed` picks the tremor.
    private struct Hand { var lean, bow, stretch, lift: Double; var seed: UInt64; var down: Bool }
    private static let hands: [Hand] = [
        Hand(lean: -0.10, bow:  0.05, stretch: 0.97, lift:  0.06, seed: 11, down: true),
        Hand(lean:  0.08, bow: -0.09, stretch: 1.02, lift: -0.05, seed: 23, down: false),
        Hand(lean: -0.05, bow:  0.07, stretch: 1.00, lift:  0.02, seed: 37, down: true),
        Hand(lean:  0.10, bow:  0.08, stretch: 0.985, lift: 0.07, seed: 41, down: false),
        Hand(lean: -0.09, bow: -0.05, stretch: 1.03, lift: -0.04, seed: 59, down: true),
    ]

    /// Closed ink outlines, one per bar; fill them.
    func outlines(originX: Double, centerY: Double, detail: Double = 1) -> [[Point]] {
        heights.enumerated().map { i, h in
            let hand = Bars.hands[i]
            let cx = originX + Double(i) * pitch + barWidth / 2
            let length = max(h * hand.stretch - barWidth, barWidth * 0.2)
            let y0 = centerY - length / 2 + hand.lift * barWidth
            // The ideal line the hand is trying to draw: a tilted, bowed vertical.
            let ideal: [Point] = (0...24).map { k in
                let u = Double(k) / 24
                let x = cx + hand.lean * barWidth * (u - 0.5) + hand.bow * barWidth * sin(.pi * u)
                return p(x, y0 + length * u)
            }
            var pen = Pen(width: barWidth, seed: hand.seed)
            pen.samples = max(Int(64 * detail), 12)
            pen.capSamples = max(Int(14 * detail), 5)
            // Alternate the drawing direction like a hand does, so the heavy
            // landing and the light lift don't all sit on the same end.
            return pen.outline(hand.down ? ideal : ideal.reversed())
        }
    }
}

// MARK: - Output helpers

struct Ink { static let black = "#0A0A0A"; static let white = "#FFFFFF" }

func svgPath(for strokes: [[Point]], transform: (Point) -> Point, decimals: Int = 2) -> String {
    func f(_ v: Double) -> String { String(format: "%.\(decimals)f", v) }
    return strokes.map { s in
        s.enumerated().map { i, pt in
            let q = transform(pt)
            return "\(i == 0 ? "M" : "L")\(f(q.x)) \(f(q.y))"
        }.joined(separator: " ")
    }.joined(separator: " ")
}

func svgBars(_ bars: Bars, originX: Double, centerY: Double, fill: String, decimals: Int = 2, detail: Double = 1) -> String {
    let d = bars.outlines(originX: originX, centerY: centerY, detail: detail).map { outline in
        svgPath(for: [outline], transform: { $0 }, decimals: decimals) + " Z"
    }.joined(separator: " ")
    return "    <path d=\"\(d)\" fill=\"\(fill)\"/>"
}

func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

func write(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    print("wrote \(path)")
}

func drawStrokes(_ strokes: [[Point]], in ctx: CGContext, width: Double, color: CGColor, transform: (Point) -> Point) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for s in strokes {
        guard let first = s.first else { continue }
        let q = transform(first)
        ctx.move(to: CGPoint(x: q.x, y: q.y))
        for pt in s.dropFirst() {
            let q = transform(pt)
            ctx.addLine(to: CGPoint(x: q.x, y: q.y))
        }
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawBars(_ bars: Bars, in ctx: CGContext, originX: Double, centerY: Double, color: CGColor) {
    ctx.saveGState()
    ctx.setFillColor(color)
    for outline in bars.outlines(originX: originX, centerY: centerY, detail: 2) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: outline[0].x, y: outline[0].y))
        for q in outline.dropFirst() { path.addLine(to: CGPoint(x: q.x, y: q.y)) }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    ctx.restoreGState()
}

/// Bitmap context in a top-left origin so the geometry above draws unflipped.
func bitmap(width: Int, height: Int, opaque: Bool) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ ctx: CGContext, to path: String) throws {
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed: \(path)") }
    print("wrote \(path)")
}

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: String) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: rgb, components: [
        CGFloat((v >> 16) & 0xff) / 255, CGFloat((v >> 8) & 0xff) / 255, CGFloat(v & 0xff) / 255, 1,
    ])!
}

// MARK: - Files

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath).path
let brand = "\(root)/Design/Brand"

let word = layout("SPEAK IT")

// 1. Wordmark SVG — stroke-based so it stays editable and exact.
do {
    let pad = strokeWidth
    let w = word.width + pad * 2
    let h = capHeight + pad * 2
    let d = svgPath(for: word.strokes) { p($0.x + pad, $0.y + pad) }
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(w))" height="\(fmt(h))" viewBox="0 0 \(fmt(w)) \(fmt(h))" role="img" aria-labelledby="title">
      <title id="title">Speak It wordmark</title>
      <path d="\(d)" fill="none" stroke="\(Ink.black)" stroke-width="\(fmt(strokeWidth))" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>

    """
    try write(svg, to: "\(brand)/SpeakIt-Wordmark.svg")
}

// 2. Wordmark PDF for the app's asset catalog (template image, tinted at runtime).
do {
    let pad = strokeWidth
    let w = word.width + pad * 2
    let h = capHeight + pad * 2
    var box = CGRect(x: 0, y: 0, width: w, height: h)
    let path = "\(root)/SpeakIt/Assets.xcassets/Wordmark.imageset/SpeakIt-Wordmark.pdf"
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: 0, y: h)
    ctx.scaleBy(x: 1, y: -1)
    drawStrokes(word.strokes, in: ctx, width: strokeWidth, color: color("#000000")) { p($0.x + pad, $0.y + pad) }
    ctx.endPDFPage()
    ctx.closePDF()
    print("wrote \(path)")
    let contents = """
    {
      "images" : [
        {
          "filename" : "SpeakIt-Wordmark.pdf",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "preserves-vector-representation" : true,
        "template-rendering-intent" : "template"
      }
    }

    """
    try write(contents, to: "\(root)/SpeakIt/Assets.xcassets/Wordmark.imageset/Contents.json")
}

// 3. App icon — 1024, opaque, near-black ground with white bars.
func renderIcon(size: Int, withWordmark: Bool, invert: Bool = false) -> CGContext {
    let s = Double(size)
    let ctx = bitmap(width: size, height: size, opaque: true)
    ctx.setFillColor(color(invert ? Ink.white : Ink.black))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let ink = color(invert ? Ink.black : Ink.white)
    if withWordmark {
        let bars = Bars.scaled(to: s * 0.46)
        drawBars(bars, in: ctx, originX: (s - bars.width) / 2, centerY: s * 0.43, color: ink)
        let scale = (s * 0.56) / word.width
        let x0 = (s - word.width * scale) / 2
        let y0 = s * 0.72
        drawStrokes(word.strokes, in: ctx, width: strokeWidth * scale, color: ink) { p(x0 + $0.x * scale, y0 + $0.y * scale) }
    } else {
        let bars = Bars.scaled(to: s * 0.56)
        drawBars(bars, in: ctx, originX: (s - bars.width) / 2, centerY: s / 2, color: ink)
    }
    return ctx
}

try writePNG(renderIcon(size: 1024, withWordmark: false), to: "\(root)/SpeakIt/Assets.xcassets/AppIcon.appiconset/SpeakIt-AppIcon-1024.png")
try writePNG(renderIcon(size: 4096, withWordmark: false), to: "\(brand)/SpeakIt-AppIcon-v2-Master-4K.png")
try writePNG(renderIcon(size: 1024, withWordmark: true), to: "\(brand)/SpeakIt-AppIcon-v2-Alt-Wordmark-1024.png")
try writePNG(renderIcon(size: 1024, withWordmark: false, invert: true), to: "\(brand)/SpeakIt-AppIcon-v2-Alt-Light-1024.png")

// Icon master SVG (matches the shipped PNG exactly).
do {
    let s = 4096.0
    let bars = Bars.scaled(to: s * 0.56)
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4096" viewBox="0 0 4096 4096" role="img" aria-labelledby="title">
      <title id="title">Speak It app icon</title>
      <rect width="4096" height="4096" fill="\(Ink.black)"/>
    \(svgBars(bars, originX: (s - bars.width) / 2, centerY: s / 2, fill: Ink.white))
    </svg>

    """
    try write(svg, to: "\(brand)/SpeakIt-AppIcon-v2-Master-4K.svg")
}

// 4. Lockups — stacked and horizontal, transparent, black ink.
do {
    // Stacked: mark above the wordmark, wordmark as wide as the mark.
    let markH = 218.4
    let bars = Bars.scaled(to: markH)
    let scale = bars.width / word.width
    let gap = 56.0
    let pad = 40.0
    let w = bars.width + pad * 2
    let h = markH + gap + capHeight * scale + pad * 2
    let d = svgPath(for: word.strokes) { p(pad + $0.x * scale, pad + markH + gap + $0.y * scale) }
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(w))" height="\(fmt(h))" viewBox="0 0 \(fmt(w)) \(fmt(h))" role="img" aria-labelledby="title">
      <title id="title">Speak It</title>
    \(svgBars(bars, originX: pad, centerY: pad + markH / 2, fill: Ink.black))
      <path d="\(d)" fill="none" stroke="\(Ink.black)" stroke-width="\(fmt(strokeWidth * scale))" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>

    """
    try write(svg, to: "\(brand)/SpeakIt-Logo-v2-Stacked.svg")

    let px = 6.0
    let ctx = bitmap(width: Int(w * px), height: Int(h * px), opaque: false)
    ctx.scaleBy(x: px, y: px)
    drawBars(bars, in: ctx, originX: pad, centerY: pad + markH / 2, color: color(Ink.black))
    drawStrokes(word.strokes, in: ctx, width: strokeWidth * scale, color: color(Ink.black)) { p(pad + $0.x * scale, pad + markH + gap + $0.y * scale) }
    try writePNG(ctx, to: "\(brand)/SpeakIt-Logo-v2-Stacked.png")
}

do {
    // Horizontal: mark at cap height, wordmark beside it.
    let scale = 1.0
    let bars = Bars.scaled(to: capHeight * 1.0)
    let gap = 44.0
    let pad = 32.0
    let w = bars.width + gap + word.width * scale + pad * 2
    let h = capHeight + pad * 2
    let d = svgPath(for: word.strokes) { p(pad + bars.width + gap + $0.x * scale, pad + $0.y * scale) }
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(w))" height="\(fmt(h))" viewBox="0 0 \(fmt(w)) \(fmt(h))" role="img" aria-labelledby="title">
      <title id="title">Speak It</title>
    \(svgBars(bars, originX: pad, centerY: pad + capHeight / 2, fill: Ink.black))
      <path d="\(d)" fill="none" stroke="\(Ink.black)" stroke-width="\(fmt(strokeWidth * scale))" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>

    """
    try write(svg, to: "\(brand)/SpeakIt-Logo-v2-Horizontal.svg")

    let px = 8.0
    let ctx = bitmap(width: Int(w * px), height: Int(h * px), opaque: false)
    ctx.scaleBy(x: px, y: px)
    drawBars(bars, in: ctx, originX: pad, centerY: pad + capHeight / 2, color: color(Ink.black))
    drawStrokes(word.strokes, in: ctx, width: strokeWidth * scale, color: color(Ink.black)) { p(pad + bars.width + gap + $0.x * scale, pad + $0.y * scale) }
    try writePNG(ctx, to: "\(brand)/SpeakIt-Logo-v2-Horizontal.png")
}

// 5. Website favicon and wordmark glyph share the same cut.
do {
    let bars = Bars.scaled(to: 20)
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
      <rect width="32" height="32" rx="7" fill="\(Ink.black)"/>
    \(svgBars(bars, originX: (32 - bars.width) / 2, centerY: 16, fill: Ink.white, detail: 0.5))
    </svg>

    """
    try write(svg, to: "\(root)/Website/assets/img/favicon.svg")
}

// 5b. The mark on its own, plus the 24-unit glyph the website topbar embeds by hand.
do {
    let bars = Bars.scaled(to: 218.4)
    let pad = 40.0
    let w = bars.width + pad * 2
    let h = bars.height + pad * 2
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(w))" height="\(fmt(h))" viewBox="0 0 \(fmt(w)) \(fmt(h))" role="img" aria-labelledby="title">
      <title id="title">Speak It mark</title>
    \(svgBars(bars, originX: pad, centerY: h / 2, fill: Ink.black))
    </svg>

    """
    try write(svg, to: "\(brand)/SpeakIt-Mark.svg")

    let glyph = Bars.scaled(to: 16)
    let topbar = svgBars(glyph, originX: (24 - glyph.width) / 2, centerY: 12, fill: "currentColor", decimals: 2, detail: 0.5)
    try write(topbar + "\n", to: "\(brand)/SpeakIt-Mark-Topbar24.svg.fragment")
}

// 6. A preview sheet so the whole system can be judged at once.
do {
    let W = 1600, H = 900
    let ctx = bitmap(width: W, height: H, opaque: true)
    ctx.setFillColor(color("#F8F8F5"))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // Icon at home-screen-ish sizes.
    for (i, size) in [180.0, 120.0, 60.0].enumerated() {
        let icon = renderIcon(size: Int(size * 2), withWordmark: false).makeImage()!
        let x = 80.0 + Double(i) * 230
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        let r = CGRect(x: x, y: Double(H) - 80 - 180, width: size, height: size)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.2237, cornerHeight: size * 0.2237, transform: nil))
        ctx.clip()
        ctx.draw(icon, in: r)
        ctx.restoreGState()
    }
    // Stacked lockup.
    let bars = Bars.scaled(to: 160)
    drawBars(bars, in: ctx, originX: 1000, centerY: 170, color: color(Ink.black))
    let s1 = bars.width / word.width
    drawStrokes(word.strokes, in: ctx, width: strokeWidth * s1, color: color(Ink.black)) { p(1000 + $0.x * s1, 300 + $0.y * s1) }
    // Big wordmark.
    let s2 = 1400.0 / word.width
    drawStrokes(word.strokes, in: ctx, width: strokeWidth * s2, color: color(Ink.black)) { p(100 + $0.x * s2, 520 + $0.y * s2) }
    // Small in-app size (caption ≈ 12pt at 2x).
    let s3 = 24.0 / capHeight
    drawStrokes(word.strokes, in: ctx, width: strokeWidth * s3, color: color("#6B6B6B")) { p(100 + $0.x * s3, 820 + $0.y * s3) }
    try writePNG(ctx, to: "\(root)/output/brand-preview.png")
}
