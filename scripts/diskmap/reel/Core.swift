// Motion toolkit: easing and springs, beat helpers, type, SF Symbols,
// screenshot sprites with masks and shadows, and particles.
import AppKit
import CoreText

// MARK: - Time

let BPM = 120.0
let BEAT = 60 / BPM
let BAR = BEAT * 4

func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
func outQuart(_ x: Double) -> Double { 1 - pow(1 - x, 4) }
func outQuint(_ x: Double) -> Double { 1 - pow(1 - x, 5) }
func outExpo(_ x: Double) -> Double { x >= 1 ? 1 : 1 - pow(2, -10 * x) }
func inQuart(_ x: Double) -> Double { x * x * x * x }
func inCubic(_ x: Double) -> Double { x * x * x }
func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func inOutQuint(_ x: Double) -> Double { x < 0.5 ? 16 * pow(x, 5) : 1 - pow(-2 * x + 2, 5) / 2 }
func inOutExpo(_ x: Double) -> Double {
	if x <= 0 { return 0 }; if x >= 1 { return 1 }
	return x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2
}

// Damped spring from 0 to 1, `dt` seconds after release. Overshoots.
func spring(_ dt: Double, f: Double = 2.2, z: Double = 0.45) -> Double {
	if dt <= 0 { return 0 }
	let w = 2 * .pi * f, wd = w * sqrt(1 - z * z)
	return 1 - exp(-z * w * dt) * (cos(wd * dt) + z * w / wd * sin(wd * dt))
}

// Decaying bump after the most recent hit.
func pulse(_ t: Double, _ hits: [Double], decay: Double = 0.12) -> Double {
	var best = 0.0
	for h in hits where t >= h { best = max(best, exp(-(t - h) / decay)) }
	return best
}

// MARK: - Colour

struct RGBA {
	var r, g, b, a: Double
	var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
	func with(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
	func lerp(_ o: RGBA, _ p: Double) -> RGBA { RGBA(r: mix(r, o.r, p), g: mix(g, o.g, p), b: mix(b, o.b, p), a: mix(a, o.a, p)) }
}
func hex(_ h: UInt32, _ a: Double = 1) -> RGBA {
	RGBA(r: Double((h >> 16) & 0xff) / 255, g: Double((h >> 8) & 0xff) / 255, b: Double(h & 0xff) / 255, a: a)
}
let SRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [RGBA], _ locations: [CGFloat]? = nil) -> CGGradient {
	CGGradient(colorsSpace: SRGB, colors: colors.map { $0.cg } as CFArray, locations: locations)!
}
let BRAND = [hex(0xC65BF0), hex(0x6E6BFF), hex(0x2F8CFF), hex(0x38D1C4)]

// MARK: - Type

struct TextPath { let path: CGPath; let width: Double }
var textCache: [String: TextPath] = [:]
func textPath(_ s: String, size: Double, weight: NSFont.Weight, kern: Double = 0) -> TextPath {
	let key = "\(s)|\(size)|\(weight.rawValue)|\(kern)"
	if let c = textCache[key] { return c }
	let font = NSFont.systemFont(ofSize: size, weight: weight)
	var attributes: [NSAttributedString.Key: Any] = [.font: font]
	if kern != 0 { attributes[.kern] = kern }
	let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attributes))
	let path = CGMutablePath()
	for run in CTLineGetGlyphRuns(line) as! [CTRun] {
		let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
		let n = CTRunGetGlyphCount(run)
		var glyphs = [CGGlyph](repeating: 0, count: n)
		var positions = [CGPoint](repeating: .zero, count: n)
		CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
		CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
		for i in 0..<n {
			if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
				path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
			}
		}
	}
	let result = TextPath(path: path, width: CTLineGetTypographicBounds(line, nil, nil, nil))
	textCache[key] = result
	return result
}

var digitCache: [String: TextPath] = [:]
func digitPath(_ s: String, size: Double) -> TextPath {
	let key = "\(s)|\(size)"
	if let c = digitCache[key] { return c }
	let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
	let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: -size * 0.02]))
	let path = CGMutablePath()
	for run in CTLineGetGlyphRuns(line) as! [CTRun] {
		let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
		let n = CTRunGetGlyphCount(run)
		var glyphs = [CGGlyph](repeating: 0, count: n)
		var positions = [CGPoint](repeating: .zero, count: n)
		CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
		CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
		for i in 0..<n {
			if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
				path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
			}
		}
	}
	let result = TextPath(path: path, width: CTLineGetTypographicBounds(line, nil, nil, nil))
	digitCache[key] = result
	return result
}

enum Fill { case color(RGBA); case gradient([RGBA]) }
struct Style {
	var size: Double
	var weight: NSFont.Weight = .bold
	var fill: Fill = .color(hex(0xF5F5F7))
	var kern: Double = 0
	static func display(_ size: Double, _ weight: NSFont.Weight = .bold, _ fill: Fill = .color(hex(0xF5F5F7))) -> Style {
		Style(size: size, weight: weight, fill: fill, kern: -size * 0.022)
	}
}

// Fills a glyph path at the current CTM (origin on the baseline, y down).
func fillText(_ ctx: CGContext, _ tp: TextPath, _ fill: Fill, gradientSpan: (Double, Double)? = nil) {
	ctx.saveGState()
	ctx.scaleBy(x: 1, y: -1)
	ctx.addPath(tp.path)
	switch fill {
	case .color(let c):
		ctx.setFillColor(c.cg); ctx.fillPath()
	case .gradient(let colors):
		ctx.clip()
		let span = gradientSpan ?? (0, tp.width)
		ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: span.0, y: 0), end: CGPoint(x: span.1, y: 0),
							   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
	}
	ctx.restoreGState()
}

func lineWidth(_ text: String, _ style: Style) -> (words: [TextPath], space: Double, total: Double) {
	let words = text.split(separator: " ").map { textPath(String($0), size: style.size, weight: style.weight, kern: style.kern) }
	let space = style.size * 0.26
	return (words, space, words.reduce(0) { $0 + $1.width } + space * Double(words.count - 1))
}

// Kinetic reveal: each word rises from behind its own baseline mask on a
// spring, and leaves upward through the same mask.
func riseText(_ ctx: CGContext, _ text: String, _ style: Style, x: Double, baseline: Double, align: Int = 1,
			  t: Double, start: Double, stagger: Double = 0.07, exit: Double? = nil, alpha: Double = 1) {
	let (words, space, total) = lineWidth(text, style)
	let left = align == 0 ? x : (align == 1 ? x - total / 2 : x - total)
	var cursor = left
	for (i, w) in words.enumerated() {
		let begin = start + Double(i) * stagger
		let p = spring(t - begin, f: 1.9, z: 0.62)
		let out = exit.map { inCubic(prog(t, $0 + Double(i) * 0.035, $0 + Double(i) * 0.035 + 0.28)) } ?? 0
		if t >= begin && out < 1 {
			ctx.saveGState()
			ctx.setAlpha(alpha)
			ctx.clip(to: CGRect(x: cursor - style.size * 0.2, y: baseline - style.size * 1.05, width: w.width + style.size * 0.4, height: style.size * 1.35))
			ctx.translateBy(x: cursor, y: baseline + (1 - p) * style.size * 1.15 - out * style.size * 1.2)
			fillText(ctx, w, style.fill, gradientSpan: (left - cursor, left - cursor + total))
			ctx.restoreGState()
		}
		cursor += w.width + space
	}
}

// A word that slams in: big and transparent to its size on a hard spring.
func slamWord(_ ctx: CGContext, _ w: TextPath, _ style: Style, x: Double, baseline: Double, t: Double, start: Double,
			  gradientSpan: (Double, Double)? = nil) {
	guard t >= start else { return }
	let p = spring(t - start, f: 2.6, z: 0.5)
	let s = mix(2.4, 1, p)
	ctx.saveGState()
	ctx.setAlpha(clamp01((t - start) / 0.06))
	ctx.translateBy(x: x + w.width / 2, y: baseline - style.size * 0.35)
	ctx.scaleBy(x: s, y: s)
	ctx.translateBy(x: -w.width / 2, y: style.size * 0.35)
	fillText(ctx, w, style.fill, gradientSpan: gradientSpan)
	ctx.restoreGState()
}

func drawLabel(_ ctx: CGContext, _ s: String, x: Double, y: Double, _ style: Style, align: Int = 1, alpha: Double = 1) {
	let tp = textPath(s, size: style.size, weight: style.weight, kern: style.kern)
	ctx.saveGState()
	ctx.setAlpha(alpha)
	ctx.translateBy(x: align == 0 ? x : (align == 1 ? x - tp.width / 2 : x - tp.width), y: y)
	fillText(ctx, tp, style.fill)
	ctx.restoreGState()
}

// MARK: - SF Symbols

var symbolCache: [String: (CGImage, Double)] = [:]
func symbolMask(_ name: String, pixels: Int) -> (CGImage, Double) {
	let key = "\(name)|\(pixels)"
	if let c = symbolCache[key] { return c }
	let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
	let symbol = base.withSymbolConfiguration(.init(pointSize: Double(pixels) * 0.8, weight: .semibold))!
	let aspect = Double(symbol.size.width / max(1, symbol.size.height))
	let w = max(1, Int(Double(pixels) * aspect)), h = pixels
	let rgba = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: SRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(cgContext: rgba, flipped: false)
	symbol.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
	NSGraphicsContext.restoreGraphicsState()
	let src = rgba.data!.assumingMemoryBound(to: UInt8.self)
	let gray = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
	let dst = gray.data!.assumingMemoryBound(to: UInt8.self)
	for i in 0..<(w * h) { dst[i] = src[i * 4 + 3] }
	let result = (gray.makeImage()!, aspect)
	symbolCache[key] = result
	return result
}

// A category-style chip: rounded square in `color` with a white symbol.
func chip(_ ctx: CGContext, _ symbol: String, color: RGBA, cx: Double, cy: Double, size: Double, alpha: Double = 1, rotation: Double = 0) {
	guard alpha > 0.01, size > 1 else { return }
	ctx.saveGState()
	ctx.setAlpha(alpha)
	ctx.translateBy(x: cx, y: cy)
	ctx.rotate(by: rotation)
	let r = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
	ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.12), blur: size * 0.35, color: CGColor(gray: 0, alpha: 0.45))
	ctx.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.23, cornerHeight: size * 0.23, transform: nil))
	ctx.setFillColor(color.cg); ctx.fillPath()
	ctx.setShadow(offset: .zero, blur: 0)
	let px = max(8, Int(pow(1.15, (log(size * 0.62) / log(1.15)).rounded())))
	let (mask, aspect) = symbolMask(symbol, pixels: px)
	var w = size * 0.6 * aspect, h = size * 0.6
	if w > size * 0.66 { h *= size * 0.66 / w; w = size * 0.66 }
	ctx.translateBy(x: -w / 2, y: h / 2); ctx.scaleBy(x: 1, y: -1)
	ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: mask)
	ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
	ctx.restoreGState()
}

func symbolGlyph(_ ctx: CGContext, _ symbol: String, color: RGBA, cx: Double, cy: Double, size: Double, alpha: Double = 1) {
	guard alpha > 0.01, size > 1 else { return }
	let px = max(8, Int(pow(1.15, (log(size) / log(1.15)).rounded())))
	let (mask, aspect) = symbolMask(symbol, pixels: px)
	let w = size * aspect, h = size
	ctx.saveGState()
	ctx.setAlpha(alpha)
	ctx.translateBy(x: cx - w / 2, y: cy + h / 2); ctx.scaleBy(x: 1, y: -1)
	ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: mask)
	ctx.setFillColor(color.cg); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
	ctx.restoreGState()
}

// MARK: - Sprites cut from real Diskmap captures

// Captures are 2× window-only JPEGs of the 1440×900 pt window (see capture.sh).
let WINDOW_RADIUS = 24.0
struct Sprite { let image: CGImage; let w: Double; let h: Double }

var captures: [String: CGImage] = [:]
var capturesDir = ""
func capture(_ name: String) -> CGImage {
	if let c = captures[name] { return c }
	let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(capturesDir)/\(name).jpg") as CFURL, nil)!
	let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
	captures[name] = img
	return img
}

// A piece of a page, in window points.
func piece(_ page: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Sprite {
	let img = capture(page).cropping(to: CGRect(x: x * 2, y: y * 2, width: w * 2, height: h * 2))!
	return Sprite(image: img, w: w, h: h)
}
func window(_ page: String) -> Sprite { piece(page, 0, 0, 1440, 900) }

// A smaller copy for shots where the window is small on screen.
func downsampled(_ s: Sprite, scale: Double) -> Sprite {
	let w = Int(Double(s.image.width) * scale), h = Int(Double(s.image.height) * scale)
	let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: SRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	ctx.interpolationQuality = .high
	ctx.draw(s.image, in: CGRect(x: 0, y: 0, width: w, height: h))
	return Sprite(image: ctx.makeImage()!, w: s.w, h: s.h)
}

// Keys out the page background so a chart floats on the stage by itself.
func keyed(_ s: Sprite, background bg: (Double, Double, Double), tolerance: Double = 7, softness: Double = 14) -> Sprite {
	let w = s.image.width, h = s.image.height
	let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: SRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	ctx.draw(s.image, in: CGRect(x: 0, y: 0, width: w, height: h))
	let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
	for i in 0..<(w * h) {
		let r = Double(p[i * 4]), g = Double(p[i * 4 + 1]), b = Double(p[i * 4 + 2])
		let d = max(abs(r - bg.0), abs(g - bg.1), abs(b - bg.2))
		let a = clamp01((d - tolerance) / softness)
		for c in 0..<4 { p[i * 4 + c] = UInt8(Double(p[i * 4 + c]) * a) }
	}
	return Sprite(image: ctx.makeImage()!, w: s.w, h: s.h)
}

func pixel(_ page: String, _ x: Double, _ y: Double) -> (Double, Double, Double) {
	let img = capture(page).cropping(to: CGRect(x: x * 2, y: y * 2, width: 1, height: 1))!
	let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: SRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
	let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
	return (Double(p[0]), Double(p[1]), Double(p[2]))
}

struct Place {
	var x: Double, y: Double          // screen position of the sprite's anchor
	var s: Double = 1                 // screen pixels per point
	var rot: Double = 0
	var alpha: Double = 1
	var ax: Double = 0.5, ay: Double = 0.5 // anchor inside the sprite (0…1)
	var sx: Double = 1                // extra horizontal scale (card flips)
}

// Draws a sprite; `radius` rounds its corners (pt), `shadow` lifts it, and
// `mask` clips in sprite points (origin top-left) before the pixels land.
func draw(_ ctx: CGContext, _ sp: Sprite, _ p: Place, radius: Double = 0, shadow: Double = 0, mask: ((CGContext) -> Void)? = nil) {
	guard p.alpha > 0.004, p.s > 0.001, abs(p.sx) > 0.001 else { return }
	ctx.saveGState()
	ctx.translateBy(x: p.x, y: p.y)
	ctx.rotate(by: p.rot)
	ctx.scaleBy(x: p.s * p.sx, y: p.s)
	ctx.translateBy(x: -sp.w * p.ax, y: -sp.h * p.ay)
	ctx.setAlpha(p.alpha)
	let bounds = CGRect(x: 0, y: 0, width: sp.w, height: sp.h)
	if shadow > 0 {
		ctx.saveGState()
		ctx.setShadow(offset: CGSize(width: 0, height: -22 * p.s * shadow), blur: 60 * p.s * shadow, color: CGColor(gray: 0, alpha: 0.55 * min(1, shadow)))
		ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: max(radius, 1), cornerHeight: max(radius, 1), transform: nil))
		ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
		ctx.restoreGState()
	}
	if radius > 0 {
		ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
	}
	mask?(ctx)
	ctx.translateBy(x: 0, y: sp.h); ctx.scaleBy(x: 1, y: -1)
	ctx.draw(sp.image, in: bounds)
	ctx.restoreGState()
}

// Maps a point inside a placed sprite (in sprite points) to the screen.
func screen(_ sp: Sprite, _ p: Place, _ x: Double, _ y: Double) -> CGPoint {
	let lx = (x - sp.w * p.ax) * p.s * p.sx, ly = (y - sp.h * p.ay) * p.s
	return CGPoint(x: p.x + lx * cos(p.rot) - ly * sin(p.rot), y: p.y + lx * sin(p.rot) + ly * cos(p.rot))
}

// Annular sector clip, for revealing a sunburst ring by ring.
func sectorClip(_ ctx: CGContext, cx: Double, cy: Double, r0: Double, r1: Double, from a0: Double, sweep: Double) {
	let p = CGMutablePath()
	p.addArc(center: CGPoint(x: cx, y: cy), radius: r1, startAngle: a0, endAngle: a0 + sweep, clockwise: false)
	p.addArc(center: CGPoint(x: cx, y: cy), radius: r0, startAngle: a0 + sweep, endAngle: a0, clockwise: true)
	p.closeSubpath()
	ctx.addPath(p); ctx.clip()
}

// MARK: - Particles

struct Burst { let t: Double; let x: Double; let y: Double; let colors: [RGBA]; let count: Int; let speed: Double; let seed: UInt32 }
func drawBurst(_ ctx: CGContext, _ b: Burst, t: Double) {
	let dt = t - b.t
	guard dt >= 0 && dt < 1.6 else { return }
	var seed = b.seed
	func rnd() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / Double(UInt32.max) }
	for i in 0..<b.count {
		let angle = rnd() * 2 * .pi, v = b.speed * (0.35 + rnd() * 0.9), size = 3 + rnd() * 7, life = 0.7 + rnd() * 0.8
		let drag = 3.2
		let dist = v * (1 - exp(-drag * dt)) / drag
		let x = b.x + cos(angle) * dist, y = b.y + sin(angle) * dist + 140 * dt * dt
		let a = clamp01(1 - dt / life)
		guard a > 0 else { continue }
		ctx.setFillColor(b.colors[i % b.colors.count].with(a).cg)
		let r = size * (0.5 + 0.5 * a)
		if i % 3 == 0 {
			ctx.fill(CGRect(x: x - r, y: y - r * 0.35, width: r * 2, height: r * 0.7))
		} else {
			ctx.fillEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
		}
	}
}
