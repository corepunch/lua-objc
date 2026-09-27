// The storyboard. Every time here sits on the 120 BPM grid (beat = 0.5 s,
// bar = 2 s), and Music.swift reads the same event lists, so sound and
// motion cannot drift apart.
import AppKit

// MARK: - Events shared with the music

let WORD_HITS = [0.5, 1.0, 1.5, 2.0]
let QUESTION = 2.5
let DROP = 4.0
let CALLOUTS = [5.5, 6.0, 6.5, 7.0]
let TILE_POPS = (0..<8).map { 8.75 + Double($0) * 0.125 }
let ROW_POPS = (0..<6).map { 10.0 + Double($0) * 0.125 }
let CARD_SLAMS = [12.0, 12.5, 13.0]
let CLEAN_POPS = (0..<6).map { 13.0 + Double($0) * 0.125 }
let CHECKS = (0..<7).map { 14.0 + Double($0) * 0.125 }
let COUNTER = 15.5
let ORBIT_POPS = (0..<6).map { 16.0 + Double($0) * 0.125 }
let TITLE_SLAMS = [16.0, 16.25, 16.5]
let SIM_SLAMS = [18.0, 18.25, 18.5]
let KIND_POPS = (0..<4).map { 19.25 + Double($0) * 0.125 }
let DIVIDER_MOVES = [20.0, 21.0, 21.5, 22.25]
let FLIPS = [22.0, 23.0]
let WALL = 24.0
let END = 26.0
let CRASHES = [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 26.0]
let WHOOSHES: [(Double, Double)] = [(7.45, 7.95), (9.9, 10.25), (11.25, 11.6), (14.9, 15.35), (16.8, 17.05), (17.8, 18.02), (18.8, 19.02), (19.8, 20.0), (23.55, 23.95)]
let RISERS: [(Double, Double)] = [(2.6, 3.95), (24.6, 25.95)]
let ROLLS: [(Double, Double)] = [(3.0, 3.93), (25.0, 25.93)]
let KICKS: [Double] = stride(from: 4.0, to: 20.0, by: 0.5).map { $0 } + [20.0, 20.75, 21.5, 22.0, 22.75, 23.5] + stride(from: 24.0, to: 26.0, by: 0.5).map { $0 }
var POPS: [Double] { CALLOUTS + TILE_POPS + ROW_POPS + CLEAN_POPS + CHECKS + ORBIT_POPS + KIND_POPS + FLIPS }
var SLAMS: [Double] { WORD_HITS + [QUESTION] + CARD_SLAMS + [COUNTER] + TITLE_SLAMS + SIM_SLAMS }

// MARK: - Assets

let STAGE = hex(0x08080A)
let LIGHT_STAGE = hex(0xE8E8ED)

let MAP_DARK = window("map-dark"), MAP_LIGHT = window("map-light")
let TREE_DARK = window("treemap-dark"), TREE_LIGHT = window("treemap-light")
let OVER_DARK = window("overview-dark"), OVER_LIGHT = window("overview-light")
let DEV_DARK = window("developer-dark")

// The sunburst, keyed off the page so it floats by itself.
let SUN_C = (x: 983.0, y: 356.0)
let SUN = keyed(piece("map-dark", SUN_C.x - 192, SUN_C.y - 192, 384, 384), background: pixel("map-dark", 700, 300))
let RINGS: [(Double, Double)] = [(0, 56), (56, 98), (98, 142), (142, 194)]

let MAP_ROWS = (0..<4).map { piece("map-dark", 236, 181 + 42 * Double($0), 277, 42) }
// Where each callout leaves the sunburst (points from its centre).
let CALLOUT_FROM: [(Double, Double)] = [(92, 30), (-96, -6), (-46, 100), (-22, -104)]

let TREE_REGION = CGRect(x: 550, y: 177, width: 866, height: 419)
let TILE_RECTS: [CGRect] = [
	CGRect(x: 550, y: 177, width: 357, height: 419), CGRect(x: 907, y: 177, width: 281, height: 254),
	CGRect(x: 907, y: 431, width: 281, height: 165), CGRect(x: 1188, y: 177, width: 228, height: 133),
	CGRect(x: 1188, y: 310, width: 228, height: 133), CGRect(x: 1188, y: 443, width: 134, height: 153),
	CGRect(x: 1322, y: 443, width: 94, height: 86), CGRect(x: 1322, y: 529, width: 94, height: 67),
]
let TILES = TILE_RECTS.map { piece("treemap-dark", $0.minX, $0.minY, $0.width, $0.height) }
let TREE_BG = pixel("treemap-dark", 1000, 820)

let LARGEST = (0..<6).map { piece("largest-dark", 238, 173 + 46 * Double($0), 1156, 46) }
let LARGEST_BAR = CGRect(x: 924, y: 15, width: 60, height: 16)
let CARDS = [piece("cleanup-dark", 234, 144, 380, 108), piece("cleanup-dark", 626, 144, 380, 108), piece("cleanup-dark", 1018, 144, 380, 108)]
let CLEAN = (0..<7).map { piece("cleanup-dark", 236, 322 + 46 * Double($0), 1161, 46) }
let CLEAN_MENU = (x: 1137.0, y: 23.0)

let SIM_CARDS = [piece("simulators-dark", 234, 144, 386, 108), piece("simulators-dark", 632, 144, 386, 108), piece("simulators-dark", 1030, 144, 386, 140)]
let SIM_TABLE = piece("simulators-dark", 236, 356, 1180, 112)
let KIND_C = (x: 349.0, y: 259.0)
let KINDS_DONUT = keyed(piece("kinds-dark", KIND_C.x - 100, KIND_C.y - 100, 200, 200), background: pixel("kinds-dark", 600, 330))
let KIND_NAMES = (0..<4).map { piece("kinds-dark", 236, 444 + 46 * Double($0), 330, 46) }
let KIND_VALUES = (0..<4).map { piece("kinds-dark", 1092, 444 + 46 * Double($0), 305, 46) }
let KIND_BG = pixel("kinds-dark", 700, 467)

let WALL_PAGES = ["overview-light", "cleanup-dark", "largest-light", "kinds-dark",
				  "developer-light", "map-dark", "treemap-light", "simulators-dark",
				  "files-dark", "xcode-light", "updates-dark", "guide-light"]
let WALL_SPRITES = WALL_PAGES.map { downsampled(window($0), scale: 0.3) }

// The logo ring from the first cut: Diskmap's categories as a donut.
let SEGMENTS: [(Double, UInt32)] = [(41, 0xB23FD9), (20, 0x3B82F6), (13, 0x34C759), (8, 0xFF453A), (8, 0x0A84FF), (6, 0x5E5CE6), (4, 0x8E8E93)]
func drawRing(_ ctx: CGContext, cx: Double, cy: Double, r: Double, width: Double, sweep: Double, rotation: Double, alpha: Double, track: RGBA = hex(0x1C1C1E)) {
	guard alpha > 0.002, width > 0.1 else { return }
	ctx.saveGState()
	ctx.setAlpha(alpha)
	ctx.setLineWidth(width)
	ctx.setLineCap(.butt)
	ctx.setStrokeColor(track.cg)
	ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
	ctx.strokePath()
	let gap = 2.2 * .pi / 180
	var angle = -Double.pi / 2 + rotation
	let limit = angle + sweep * 2 * .pi
	for (share, color) in SEGMENTS {
		let span = share / 100 * 2 * .pi
		let end = min(angle + span - gap, limit)
		if end > angle {
			ctx.setStrokeColor(hex(color).cg)
			ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: angle, endAngle: end, clockwise: false)
			ctx.strokePath()
		}
		angle += span
	}
	ctx.restoreGState()
}

// MARK: - Helpers

let W = 1920.0, H = 1080.0
let HEAD = Style.display(78, .semibold)
let SUB = Style.display(32, .regular, .color(hex(0x98989D)))

func shake(_ t: Double, _ hits: [Double], amount: Double) -> CGPoint {
	var dx = 0.0, dy = 0.0
	for h in hits where t >= h && t < h + 0.4 {
		let e = exp(-(t - h) / 0.08) * amount
		dx += sin((t - h) * 97) * e; dy += cos((t - h) * 83) * e
	}
	return CGPoint(x: dx, y: dy)
}

func stage(_ ctx: CGContext, _ t: Double) {
	ctx.setFillColor(STAGE.cg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
	let beat = pulse(t, KICKS, decay: 0.18)
	let blobs: [(RGBA, Double, Double, Double)] = [
		(hex(0x9B3FE0), 520 + 180 * sin(t * 0.35), 380 + 120 * cos(t * 0.27), 760),
		(hex(0x1E6BFF), 1450 + 160 * cos(t * 0.31), 700 + 140 * sin(t * 0.22), 820),
		(hex(0x1FB5A8), 1000 + 260 * sin(t * 0.19 + 2), 1050 + 60 * cos(t * 0.4), 700),
	]
	for (c, x, y, r) in blobs {
		let g = gradient([c.with(0.22 + 0.06 * beat), c.with(0)])
		ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
	}
	// Vignette.
	let v = gradient([hex(0, 0), hex(0, 0.55)])
	ctx.drawRadialGradient(v, startCenter: CGPoint(x: 960, y: 540), startRadius: 500, endCenter: CGPoint(x: 960, y: 540), endRadius: 1250, options: [.drawsAfterEndLocation])
}

func sweepLight(_ ctx: CGContext, rect: CGRect, p: Double) {
	guard p > 0 && p < 1 else { return }
	ctx.saveGState()
	ctx.clip(to: rect)
	let x = rect.minX - 400 + (rect.width + 800) * p
	let g = gradient([hex(0xFFFFFF, 0), hex(0xFFFFFF, 0.16), hex(0xFFFFFF, 0)])
	ctx.translateBy(x: x, y: rect.midY)
	ctx.rotate(by: 0.35)
	ctx.drawLinearGradient(g, start: CGPoint(x: -160, y: 0), end: CGPoint(x: 160, y: 0), options: [])
	ctx.restoreGState()
}

// Places the sunburst so its centre is at (x, y).
func sunPlace(x: Double, y: Double, s: Double, rot: Double = 0, alpha: Double = 1) -> Place {
	Place(x: x, y: y, s: s, rot: rot, alpha: alpha)
}

// Places a window so window point (px, py) lands on (x, y).
func windowPlace(_ px: Double, _ py: Double, x: Double, y: Double, s: Double, alpha: Double = 1, rot: Double = 0, sx: Double = 1) -> Place {
	Place(x: x, y: y, s: s, rot: rot, alpha: alpha, ax: px / 1440, ay: py / 900, sx: sx)
}

// MARK: - 1 · 0–4 s: the question

func intro(_ ctx: CGContext, _ t: Double) {
	guard t < 4.25 else { return }
	let big = Style.display(150, .bold)
	let words = ["Your", "disk", "is", "full."].map { textPath($0, size: big.size, weight: big.weight, kern: big.kern) }
	let space = big.size * 0.26
	let total = words.reduce(0) { $0 + $1.width } + space * 3
	let sh = shake(t, WORD_HITS, amount: 10)
	if t < 2.7 {
		let squash = inQuart(prog(t, 2.42, 2.62))
		ctx.saveGState()
		ctx.translateBy(x: 960 + sh.x, y: 540 + sh.y)
		let zoom = mix(1, 1.07, prog(t, 0.5, 2.5))
		ctx.scaleBy(x: zoom * (1 + squash * 0.3), y: zoom * (1 - squash))
		ctx.translateBy(x: -960, y: -540)
		var x = 960 - total / 2
		for (i, w) in words.enumerated() {
			slamWord(ctx, w, big, x: x, baseline: 592, t: t, start: WORD_HITS[i])
			x += w.width + space
		}
		ctx.restoreGState()
	}
	// "Full of what?" shrinks into the logo ring, then blows out on the drop.
	let shrink = inOutCubic(prog(t, 3.05, 3.65))
	let blow = outExpo(prog(t, DROP, DROP + 0.22))
	let s = mix(1, 0.4, shrink) * (1 + blow * 2.2)
	ctx.saveGState()
	ctx.translateBy(x: 960, y: 540)
	ctx.scaleBy(x: s, y: s)
	ctx.translateBy(x: -960, y: -540)
	riseText(ctx, "Full of what?", Style.display(150, .bold, .gradient(BRAND)), x: 960, baseline: 592, t: t, start: QUESTION - 0.02, stagger: 0.06, alpha: 1 - blow)
	ctx.restoreGState()
	let sweep = outQuart(prog(t, 3.0, 3.85))
	let wave = outExpo(prog(t, DROP, DROP + 0.45))
	drawRing(ctx, cx: 960, cy: 538, r: 262 + wave * 700, width: 34 * (1 - wave), sweep: sweep,
			 rotation: -0.35 * (1 - outQuint(prog(t, 3.0, 3.9))), alpha: prog(t, 2.95, 3.05) * (1 - wave))
}

// MARK: - 2 · 4–8 s: the sunburst

func sunScale(_ t: Double) -> Double {
	2.0 * mix(0.7, 1, spring(t - DROP, f: 1.5, z: 0.55)) * (1 + 0.014 * pulse(t, KICKS, decay: 0.14))
}

func drawSun(_ ctx: CGContext, _ t: Double, place: Place, reveal: Bool) {
	let rot = -0.5 * (1 - spring(t - DROP, f: 1.2, z: 0.62))
	for (k, ring) in RINGS.enumerated() {
		var p = place
		if k > 0 { p.rot += rot }
		let start = DROP + Double(k - 1) * 0.125
		let sweep = reveal ? (k == 0 ? 1 : outQuart(prog(t, start, start + 0.38))) : 1
		let grow = reveal && k == 0 ? spring(t - DROP, f: 2.4, z: 0.4) : 1
		if sweep <= 0 || grow <= 0 { continue }
		draw(ctx, SUN, p) { c in
			if k == 0 {
				let r = ring.1 * grow
				c.addEllipse(in: CGRect(x: 192 - r, y: 192 - r, width: r * 2, height: r * 2)); c.clip()
			} else {
				sectorClip(c, cx: 192, cy: 192, r0: ring.0, r1: k == 3 ? 260 : ring.1, from: -.pi / 2, sweep: sweep * 2 * .pi)
			}
		}
	}
}

let SUN_AT = (x: 1270.0, y: 548.0)
let WIN3 = (x: 960.0, y: 612.0, s: 0.78)

func mapScene(_ ctx: CGContext, _ t: Double) {
	guard t >= DROP - 0.02 && t < 8.2 else { return }
	let s = sunScale(t)
	let q = inOutQuint(prog(t, 7.45, 8.0))
	// Glow behind the chart, breathing with the kick.
	let glowA = (0.45 + 0.2 * pulse(t, KICKS, decay: 0.2)) * clamp01((t - DROP) / 0.3) * (1 - q)
	ctx.drawRadialGradient(gradient([hex(0x8E44E8, glowA), hex(0x2F6BFF, glowA * 0.4), hex(0, 0)], [0, 0.45, 1]),
						   startCenter: CGPoint(x: SUN_AT.x, y: SUN_AT.y), startRadius: 0,
						   endCenter: CGPoint(x: SUN_AT.x, y: SUN_AT.y), endRadius: 620, options: [])

	// The window grows around the chart: same pixels, so the seam is invisible.
	let ws = exp(mix(log(s), log(WIN3.s), q))
	let target = CGPoint(x: WIN3.x + (SUN_C.x - 720) * WIN3.s, y: WIN3.y + (SUN_C.y - 450) * WIN3.s)
	let anchor = CGPoint(x: mix(SUN_AT.x, target.x, q), y: mix(SUN_AT.y, target.y, q))
	if t >= 7.45 && t < 7.98 {
		let reveal = outQuart(prog(t, 7.5, 7.98))
		let wp = windowPlace(SUN_C.x, SUN_C.y, x: anchor.x, y: anchor.y, s: ws)
		draw(ctx, MAP_DARK, wp, radius: WINDOW_RADIUS, shadow: reveal) { c in
			let r = mix(194, 1300, reveal)
			c.addEllipse(in: CGRect(x: SUN_C.x - r, y: SUN_C.y - r, width: r * 2, height: r * 2)); c.clip()
		}
	}
	drawSun(ctx, t, place: sunPlace(x: anchor.x, y: anchor.y, s: t >= 7.45 ? ws : s, alpha: 1 - prog(t, 7.85, 7.98)), reveal: true)

	riseText(ctx, "Every byte,", Style.display(112), x: 140, baseline: 432, align: 0, t: t, start: 4.5, exit: 7.3)
	riseText(ctx, "mapped.", Style.display(112, .bold, .gradient(BRAND)), x: 140, baseline: 552, align: 0, t: t, start: 4.9, exit: 7.34)
	riseText(ctx, "Every category. Every folder. At a glance.", Style.display(34, .regular, .color(hex(0xA1A1A6))), x: 142, baseline: 626, align: 0,
			 t: t, start: 5.2, stagger: 0.035, exit: 7.2)

	// Callouts: real list rows fly out of their own segment.
	for (i, row) in MAP_ROWS.enumerated() {
		let pop = CALLOUTS[i]
		guard t >= pop else { continue }
		let p = spring(t - pop, f: 1.8, z: 0.62)
		let from = CGPoint(x: SUN_AT.x + CALLOUT_FROM[i].0 * s, y: SUN_AT.y + CALLOUT_FROM[i].1 * s)
		let rest = CGPoint(x: 140 + row.w * 1.55 / 2, y: 704 + Double(i) * 78)
		var x = mix(from.x, rest.x, p), y = mix(from.y, rest.y, p), sc = mix(0.25, 1.55, p)
		// Home to the row's place in the window.
		let home = inOutCubic(prog(t, 7.45 + Double(i) * 0.03, 7.95 + Double(i) * 0.03))
		if home > 0 {
			let hp = screen(MAP_DARK, windowPlace(SUN_C.x, SUN_C.y, x: anchor.x, y: anchor.y, s: ws), 236 + row.w / 2, 181 + 21 + 42 * Double(i))
			x = mix(rest.x, hp.x, home); y = mix(rest.y, hp.y, home); sc = exp(mix(log(1.55), log(ws), home))
		}
		draw(ctx, row, Place(x: x, y: y, s: sc, alpha: clamp01((t - pop) / 0.08) * (1 - prog(t, 7.95, 8.05))), radius: 8 * (1 - home), shadow: 0.7 * (1 - home))
	}
}

// MARK: - 3 · 8–12 s: rings → rectangles, then the largest items

func windowPunch(_ t: Double, _ at: Double) -> Double {
	t < at ? 1 : 1 + 0.028 * sin((t - at) * 2 * .pi * 3.2) * exp(-(t - at) / 0.16)
}

func treemapScene(_ ctx: CGContext, _ t: Double) {
	guard t >= 7.98 && t < 10.3 else { return }
	let s = WIN3.s * windowPunch(t, 8.0)
	let out = inQuart(prog(t, 9.95, 10.25))
	let x = WIN3.x - out * 2300
	let place = Place(x: x, y: WIN3.y, s: s)
	let swap = prog(t, 8.5, 8.62)
	if swap < 1 { draw(ctx, MAP_DARK, place, radius: WINDOW_RADIUS, shadow: 1) }
	if swap > 0 {
		var p = place; p.alpha = swap
		draw(ctx, TREE_DARK, p, radius: WINDOW_RADIUS, shadow: swap)
		// Clear the chart area; the tiles pop in on their own.
		let o = screen(TREE_DARK, place, TREE_REGION.minX, TREE_REGION.minY)
		ctx.setFillColor(CGColor(srgbRed: TREE_BG.0 / 255, green: TREE_BG.1 / 255, blue: TREE_BG.2 / 255, alpha: swap))
		ctx.fill(CGRect(x: o.x - 1, y: o.y - 1, width: TREE_REGION.width * s + 2, height: TREE_REGION.height * s + 2))
		for (i, tile) in TILES.enumerated() {
			let pop = TILE_POPS[i]
			guard t >= pop else { continue }
			let r = TILE_RECTS[i]
			let c = screen(TREE_DARK, place, r.midX, r.midY)
			let k = spring(t - pop, f: 2.3, z: 0.5)
			draw(ctx, tile, Place(x: c.x, y: c.y, s: s * k, rot: 0.25 * (1 - k), alpha: clamp01((t - pop) / 0.06)), radius: 3 * (1 - k))
		}
	}
	// The sunburst spins away as the tiles arrive.
	let gone = inQuart(prog(t, 8.45, 8.78))
	if gone < 1 {
		let c = screen(MAP_DARK, place, SUN_C.x, SUN_C.y)
		draw(ctx, SUN, Place(x: c.x, y: c.y, s: s * (1 - gone), rot: gone * 1.6))
	}
	sweepLight(ctx, rect: CGRect(x: x - 1440 * s / 2, y: WIN3.y - 450 * s, width: 1440 * s, height: 900 * s), p: prog(t, 9.2, 9.75))
	riseText(ctx, "Rings or rectangles.", HEAD, x: 960, baseline: 176, t: t, start: 8.12, exit: 9.72)
	riseText(ctx, "Click any group to look inside.", SUB, x: 960, baseline: 236, t: t, start: 8.32, stagger: 0.035, exit: 9.68)
}

func rowY(_ i: Int) -> Double { 330 + Double(i) * 70 }

func largestScene(_ ctx: CGContext, _ t: Double) {
	guard t >= 9.95 && t < 12.4 else { return }
	riseText(ctx, "Find what’s big.", HEAD, x: 960, baseline: 176, t: t, start: 10.1, exit: 11.2)
	riseText(ctx, "The largest items on your disk, ranked.", SUB, x: 960, baseline: 236, t: t, start: 10.28, stagger: 0.035, exit: 11.16)
	for (i, row) in LARGEST.enumerated() {
		let pop = ROW_POPS[i]
		guard t >= pop else { continue }
		let k = spring(t - pop, f: 1.7, z: 0.68)
		var x = mix(960 + 1700, 960, k), y = rowY(i), s = 1.22
		var alpha = 1.0
		if i == 4 {
			// Xcode DerivedData carries on into Clean Up.
			let lift = inOutCubic(prog(t, 11.3, 11.75))
			y = mix(rowY(i), 540, lift); s = mix(1.22, 1.42, lift)
			let land = inOutCubic(prog(t, 11.8, 12.25))
			y = mix(y, cleanY(0), land); s = mix(s, 1.18, land)
			alpha = 1 - prog(t, 12.1, 12.25)
		} else {
			let j = Double(i < 4 ? i : i - 1)
			x -= 2600 * inQuart(prog(t, 11.25 + j * 0.03, 11.55 + j * 0.03))
		}
		let place = Place(x: x, y: y, s: s, alpha: alpha)
		let bar = outQuart(prog(t, pop + 0.15, pop + 0.6))
		draw(ctx, row, place, radius: 9, shadow: 0.6) { c in
			c.addRect(CGRect(x: 0, y: 0, width: row.w, height: row.h))
			c.addRect(LARGEST_BAR)
			c.clip(using: .evenOdd)
		}
		draw(ctx, row, place, radius: 9) { c in
			c.clip(to: CGRect(x: LARGEST_BAR.minX, y: LARGEST_BAR.minY, width: LARGEST_BAR.width * bar, height: LARGEST_BAR.height))
		}
		if i == 4 {
			// A rebuildable badge pulse on the status icon.
			let pp = prog(t, 11.55, 12.0)
			if pp > 0 && pp < 1 {
				let c = screen(row, place, 852, 23)
				ctx.setStrokeColor(hex(0x34C759, 1 - pp).cg)
				ctx.setLineWidth(4 * (1 - pp) + 1)
				let r = 12 + pp * 70
				ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
			}
			if t >= 12.1 {
				draw(ctx, CLEAN[0], Place(x: 960, y: y, s: s, alpha: prog(t, 12.1, 12.25)), radius: 9, shadow: 0.6)
			}
		}
	}
}

// MARK: - 4 · 12–16 s: Clean Up

func cleanY(_ i: Int) -> Double { 492 + Double(i) * 62 }
let CARD_Y = 346.0
func cardX(_ k: Int) -> Double { 960 + Double(k - 1) * 560 }

func cleanupScene(_ ctx: CGContext, _ t: Double) {
	guard t >= 12.0 && t < 16.3 else { return }
	let away = inOutCubic(prog(t, 15.38, 15.55))
	riseText(ctx, "Clean up with confidence.", HEAD, x: 960, baseline: 176, t: t, start: 12.1, exit: 13.85)
	riseText(ctx, "Diskmap knows what’s rebuildable — and what’s your work.", SUB, x: 960, baseline: 236, t: t, start: 12.3, stagger: 0.03, exit: 13.8)
	let absorb = pulse(t, [15.28], decay: 0.12)
	for (k, card) in CARDS.enumerated() {
		let slam = CARD_SLAMS[k]
		guard t >= slam else { continue }
		let sp = spring(t - slam, f: 2.3, z: 0.5)
		let s = 1.38 * mix(1.75, 1, sp) * (k == 0 ? 1 + 0.09 * absorb : 1) * (1 - 0.25 * away)
		draw(ctx, card, Place(x: cardX(k), y: CARD_Y - 34 * (1 - sp), s: s, alpha: clamp01((t - slam) / 0.07) * (1 - away)), radius: 12, shadow: 0.7)
	}
	for (i, row) in CLEAN.enumerated() {
		let enter = i == 0 ? 12.2 : CLEAN_POPS[i - 1]
		guard t >= enter else { continue }
		let k = i == 0 ? 1 : spring(t - enter, f: 1.9, z: 0.6)
		var x = 960.0, y = cleanY(i) + (1 - k) * 160, s = 1.18
		var alpha = i == 0 ? 1 : clamp01((t - enter) / 0.08)
		// Into the Rebuildable card.
		let fly = inCubic(prog(t, 14.9 + Double(i) * 0.04, 15.25 + Double(i) * 0.04))
		if fly > 0 {
			x = mix(x, cardX(0), fly); y = mix(y, CARD_Y, fly); s = mix(s, 0.1, fly); alpha *= 1 - fly * fly
		}
		let place = Place(x: x, y: y, s: s, alpha: alpha)
		draw(ctx, row, place, radius: 9, shadow: 0.55)
		let check = CHECKS[i]
		if t >= check {
			let c = screen(row, place, CLEAN_MENU.x, CLEAN_MENU.y)
			let cs = spring(t - check, f: 2.6, z: 0.4) * 22 * s
			ctx.setFillColor(hex(0x2C2C2E, alpha).cg)
			ctx.fillEllipse(in: CGRect(x: c.x - 13 * s, y: c.y - 13 * s, width: 26 * s, height: 26 * s))
			symbolGlyph(ctx, "checkmark.circle.fill", color: hex(0x34C759), cx: c.x, cy: c.y, size: cs, alpha: alpha)
			let flash = pulse(t, [check], decay: 0.15)
			if flash > 0.01 {
				let o = screen(row, place, 0, 0)
				ctx.setFillColor(hex(0x34C759, 0.18 * flash * alpha).cg)
				ctx.fill(CGRect(x: o.x, y: o.y, width: row.w * s, height: row.h * s))
			}
		}
	}
	// The payoff counter.
	if t >= COUNTER - 0.05 {
		// Digits tick in fixed-width slots; the unit holds still.
		let v = (19.8 * outQuart(prog(t, COUNTER - 0.05, COUNTER + 0.35)) * 10).rounded() / 10
		let fill = Fill.gradient([hex(0x34C759), hex(0x30D5C8), hex(0x64D2FF)])
		let digits = digitPath(String(format: "%.1f", v), size: 230)
		let unit = textPath(" GB", size: 230, weight: .heavy, kern: -5)
		let finalDigits = digitPath("19.8", size: 230)
		let total = finalDigits.width + unit.width
		let sp = spring(t - COUNTER, f: 2.2, z: 0.45)
		ctx.saveGState()
		ctx.translateBy(x: 960, y: 520)
		ctx.scaleBy(x: mix(1.8, 1, sp), y: mix(1.8, 1, sp))
		ctx.setAlpha(clamp01((t - COUNTER + 0.05) / 0.08) * (1 - prog(t, 15.93, 16.0)))
		ctx.translateBy(x: -total / 2, y: 80)
		ctx.saveGState()
		ctx.translateBy(x: finalDigits.width - digits.width, y: 0)
		fillText(ctx, digits, fill, gradientSpan: (digits.width - finalDigits.width, digits.width - finalDigits.width + total))
		ctx.restoreGState()
		ctx.translateBy(x: finalDigits.width, y: 0)
		fillText(ctx, unit, fill, gradientSpan: (-finalDigits.width, unit.width))
		ctx.restoreGState()
		riseText(ctx, "rebuildable, ready to clear.", Style.display(44, .medium, .color(hex(0xC7C7CC))), x: 960, baseline: 690, t: t, start: 15.62, stagger: 0.04, exit: 15.9)
	}
	drawBurst(ctx, Burst(t: COUNTER, x: 960, y: 500, colors: [hex(0x34C759), hex(0x30D5C8), hex(0xFFFFFF), hex(0x64D2FF)], count: 110, speed: 1700, seed: 7), t: t)
}

// MARK: - 5 · 16–20 s: developer montage

let ORBIT: [(String, UInt32)] = [("hammer.fill", 0x1C7CF4), ("iphone", 0x007AFF), ("shippingbox.fill", 0xFF9500),
								 ("cube.fill", 0x32ADE6), ("terminal.fill", 0x5E5CE6), ("sparkles", 0xAF52DE)]

func devTitle(_ ctx: CGContext, _ t: Double) {
	guard t >= 15.98 && t < 17.1 else { return }
	let out = inQuart(prog(t, 16.85, 17.05))
	let zoom = 1 + out * 2.2
	ctx.saveGState()
	ctx.translateBy(x: 960, y: 540); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -960, y: -540)
	ctx.setAlpha(1 - out)
	func orbit(front: Bool) {
		for (i, (sym, color)) in ORBIT.enumerated() {
			let pop = ORBIT_POPS[i]
			guard t >= pop else { continue }
			let a = Double(i) / 6 * 2 * .pi + (t - 16) * 0.9
			let depth = sin(a)
			if (depth > 0) != front { continue }
			let k = spring(t - pop, f: 2.2, z: 0.45)
			let size = 104 * (0.78 + 0.3 * (depth + 1) / 2) * k
			chip(ctx, sym, color: hex(color), cx: 960 + cos(a) * 700, cy: 560 + depth * 300, size: size,
				 alpha: (0.55 + 0.45 * (depth + 1) / 2), rotation: 0.3 * (1 - k))
		}
	}
	orbit(front: false)
	let style = Style.display(128, .bold)
	let words = ["Made", "for", "developers."]
	let paths = words.map { textPath($0, size: style.size, weight: style.weight, kern: style.kern) }
	let space = style.size * 0.26
	let total = paths.reduce(0) { $0 + $1.width } + space * 2
	var x = 960 - total / 2
	for (i, w) in paths.enumerated() {
		let st = i == 2 ? Style.display(128, .bold, .gradient(BRAND)) : style
		slamWord(ctx, w, st, x: x, baseline: 590, t: t, start: TITLE_SLAMS[i], gradientSpan: i == 2 ? (0, w.width) : nil)
		x += w.width + space
	}
	orbit(front: true)
	ctx.restoreGState()
}

func devWindow(_ ctx: CGContext, _ t: Double) {
	guard t >= 17.0 && t < 18.05 else { return }
	riseText(ctx, "Xcode, packages, containers.", HEAD, x: 960, baseline: 150, t: t, start: 17.05, exit: 17.82)
	let k = spring(t - 17.0, f: 1.6, z: 0.72)
	let push = inOutCubic(prog(t, 17.35, 17.95))
	let out = inQuart(prog(t, 17.88, 18.02))
	let s = exp(mix(log(0.74), log(1.35), push)) * (1 + out * 0.6)
	let px = mix(720, 760, push), py = mix(450, 330, push)
	let place = windowPlace(px, py, x: mix(960 + 1500, 960, k), y: mix(640, 560, push), s: s, alpha: 1 - out, rot: 0.14 * (1 - k))
	draw(ctx, DEV_DARK, place, radius: WINDOW_RADIUS, shadow: 1)
	let o = screen(DEV_DARK, place, 0, 0)
	sweepLight(ctx, rect: CGRect(x: o.x, y: o.y, width: 1440 * s, height: 900 * s), p: prog(t, 17.3, 17.85))
}

func simScene(_ ctx: CGContext, _ t: Double) {
	guard t >= 17.98 && t < 19.05 else { return }
	let out = inQuart(prog(t, 18.86, 19.02))
	riseText(ctx, "Simulators & runtimes.", HEAD, x: 960, baseline: 210, t: t, start: 18.05, exit: 18.8)
	for (k, card) in SIM_CARDS.enumerated() {
		let slam = SIM_SLAMS[k]
		guard t >= slam else { continue }
		let sp = spring(t - slam, f: 2.4, z: 0.48)
		let s = 1.36 * mix(1.8, 1, sp) * (1 - out * 0.3)
		let x = 960 + Double(k - 1) * 556
		draw(ctx, card, Place(x: x - out * 900 * Double(1 - k), y: 330 + card.h * 1.36 / 2 - 34 * (1 - sp), s: s, alpha: clamp01((t - slam) / 0.07) * (1 - out)), radius: 12, shadow: 0.7)
	}
	let up = spring(t - 18.5, f: 1.8, z: 0.7)
	if t >= 18.5 {
		draw(ctx, SIM_TABLE, Place(x: 960, y: mix(1250, 700, up), s: 1.36 * (1 - out * 0.3), alpha: 1 - out), radius: 10, shadow: 0.7)
	}
}

func kindsScene(_ ctx: CGContext, _ t: Double) {
	guard t >= 18.98 && t < 20.05 else { return }
	let out = inQuart(prog(t, 19.85, 20.0))
	riseText(ctx, "Every file type.", HEAD, x: 960, baseline: 170, t: t, start: 19.05, exit: 19.8)
	let s = 2.25 * (1 - out)
	let place = Place(x: 560, y: 610, s: s)
	let sweep = outQuart(prog(t, 19.0, 19.42))
	let grow = spring(t - 19.0, f: 2.4, z: 0.42)
	draw(ctx, KINDS_DONUT, place) { c in
		c.addEllipse(in: CGRect(x: 100 - 64 * grow, y: 100 - 64 * grow, width: 128 * grow, height: 128 * grow)); c.clip()
	}
	draw(ctx, KINDS_DONUT, place) { c in sectorClip(c, cx: 100, cy: 100, r0: 60, r1: 100, from: -.pi / 2, sweep: sweep * 2 * .pi) }
	for i in 0..<4 {
		let pop = KIND_POPS[i]
		guard t >= pop else { continue }
		let k = spring(t - pop, f: 1.9, z: 0.62)
		let s = 1.2, gap = 12.0
		let w = (KIND_NAMES[i].w + KIND_VALUES[i].w) * s + gap
		let left = mix(1920 + 100, 930, k) + out * 1400
		let y = 500 + Double(i) * 76
		ctx.saveGState()
		ctx.setAlpha(clamp01((t - pop) / 0.08) * (1 - out))
		ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: CGColor(gray: 0, alpha: 0.5))
		ctx.addPath(CGPath(roundedRect: CGRect(x: left, y: y - 46 * s / 2, width: w, height: 46 * s), cornerWidth: 11, cornerHeight: 11, transform: nil))
		ctx.setFillColor(CGColor(srgbRed: KIND_BG.0 / 255, green: KIND_BG.1 / 255, blue: KIND_BG.2 / 255, alpha: 1)); ctx.fillPath()
		ctx.restoreGState()
		let a = clamp01((t - pop) / 0.08) * (1 - out)
		draw(ctx, KIND_NAMES[i], Place(x: left, y: y, s: s, alpha: a, ax: 0))
		let vp = Place(x: left + KIND_NAMES[i].w * s + gap, y: y, s: s, alpha: a, ax: 0)
		let bar = outQuart(prog(t, pop + 0.12, pop + 0.5))
		draw(ctx, KIND_VALUES[i], vp) { c in
			c.addRect(CGRect(x: 0, y: 0, width: 305, height: 46)); c.addRect(CGRect(x: 70, y: 14, width: 60, height: 18)); c.clip(using: .evenOdd)
		}
		draw(ctx, KIND_VALUES[i], vp) { c in c.clip(to: CGRect(x: 70, y: 14, width: 60 * bar, height: 18)) }
	}
}

// MARK: - 6 · 20–24 s: light and dark

func dividerX(_ t: Double) -> Double {
	let keys: [(Double, Double, Double)] = [(20.0, 20.42, 960), (21.0, 21.3, 1360), (21.5, 21.8, 580), (22.25, 22.55, 960), (23.5, 23.85, 1990)]
	var x = 1990.0
	for (t0, t1, target) in keys {
		if t >= t1 { x = target; continue }
		if t >= t0 { return mix(x, target, inOutExpo(prog(t, t0, t1))) }
		break
	}
	return x
}

func lightDark(_ ctx: CGContext, _ t: Double) {
	guard t >= 19.98 && t < 24.1 else { return }
	let dx = dividerX(t)
	// Page flips on the beat: map → overview → treemap.
	var page = 0, sx = 1.0
	for (i, f) in FLIPS.enumerated() {
		let p = prog(t, f, f + 0.32)
		if p >= 0.5 { page = i + 1 }
		if p > 0 && p < 1 { sx = max(0.004, abs(cos(.pi * p))) }
	}
	let dark = [MAP_DARK, OVER_DARK, TREE_DARK][page], light = [MAP_LIGHT, OVER_LIGHT, TREE_LIGHT][page]
	let k = spring(t - 20.0, f: 1.7, z: 0.6)
	let leave = inOutQuint(prog(t, 23.55, 24.0))
	let s = 0.8 * mix(0.55, 1, k) * (1 - leave * 0.62) * windowPunch(t, 22.16) * windowPunch(t, 23.16)
	let place = Place(x: 960, y: 612 - leave * 70, s: s, sx: sx)
	// Split stage.
	ctx.saveGState()
	ctx.clip(to: CGRect(x: dx, y: 0, width: W - dx + 1, height: H))
	ctx.setFillColor(LIGHT_STAGE.cg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
	ctx.drawRadialGradient(gradient([hex(0xFFFFFF, 0.9), hex(0xFFFFFF, 0)]), startCenter: CGPoint(x: 1300, y: 400), startRadius: 0,
						   endCenter: CGPoint(x: 1300, y: 400), endRadius: 900, options: [])
	draw(ctx, light, place, radius: WINDOW_RADIUS, shadow: 0.5)
	riseText(ctx, "Beautiful in light. And dark.", Style.display(78, .semibold, .color(hex(0x1D1D1F))), x: 960, baseline: 176, t: t, start: 20.3, exit: 23.45)
	riseText(ctx, "Native macOS, down to the last control.", Style.display(32, .regular, .color(hex(0x6E6E73))), x: 960, baseline: 236, t: t, start: 20.5, stagger: 0.035, exit: 23.4)
	ctx.restoreGState()
	ctx.saveGState()
	ctx.clip(to: CGRect(x: 0, y: 0, width: dx, height: H))
	draw(ctx, dark, place, radius: WINDOW_RADIUS, shadow: 1)
	riseText(ctx, "Beautiful in light. And dark.", HEAD, x: 960, baseline: 176, t: t, start: 20.3, exit: 23.45)
	riseText(ctx, "Native macOS, down to the last control.", SUB, x: 960, baseline: 236, t: t, start: 20.5, stagger: 0.035, exit: 23.4)
	ctx.restoreGState()
	// Divider with an appearance knob.
	if dx > -10 && dx < W + 10 {
		ctx.setFillColor(hex(0xFFFFFF, 0.85).cg)
		ctx.fill(CGRect(x: dx - 1.5, y: 0, width: 3, height: H))
		ctx.drawRadialGradient(gradient([hex(0xFFFFFF, 0.35), hex(0xFFFFFF, 0)]), startCenter: CGPoint(x: dx, y: 540), startRadius: 0,
							   endCenter: CGPoint(x: dx, y: 540), endRadius: 260, options: [])
		let knob = 64 * (1 + 0.15 * pulse(t, DIVIDER_MOVES, decay: 0.15))
		ctx.saveGState()
		ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(gray: 0, alpha: 0.5))
		ctx.setFillColor(hex(0xFFFFFF).cg)
		ctx.fillEllipse(in: CGRect(x: dx - knob / 2, y: 540 - knob / 2, width: knob, height: knob))
		ctx.restoreGState()
		symbolGlyph(ctx, "circle.lefthalf.filled", color: hex(0x1D1D1F), cx: dx, cy: 540, size: knob * 0.55)
	}
}

// MARK: - 7 · 24–26 s: the wall, then into the sunburst

func wall(_ ctx: CGContext, _ t: Double) {
	guard t >= 23.9 && t < 26.02 else { return }
	let cols = 4, rows = 3
	let cellW = 600.0, cellH = 390.0, ws = 0.37
	let target = 5 // map-dark: column 1, row 1
	func cellCenter(_ i: Int) -> CGPoint {
		CGPoint(x: (Double(i % cols) - 1.5) * cellW, y: (Double(i / cols) - 1) * cellH)
	}
	let tc = cellCenter(target)
	let sunInWall = CGPoint(x: tc.x + (SUN_C.x - 720) * ws, y: tc.y + (SUN_C.y - 450) * ws)
	let dive = inOutExpo(prog(t, 25.3, 26.0))
	let pan = mix(420, -380, inOutCubic(prog(t, 23.9, 25.5)))
	let focus = CGPoint(x: mix(pan, sunInWall.x, dive), y: mix(0, sunInWall.y, dive))
	let zoom = exp(mix(0, log(16), dive)) * (1 + 0.02 * pulse(t, KICKS, decay: 0.14))
	let rot = mix(-0.16, 0, dive)
	for i in 0..<(cols * rows) {
		let c = cellCenter(i)
		let d = hypot(c.x, c.y) / 1500
		let k = spring(t - 23.95 - d * 0.35, f: 2.0, z: 0.55)
		let vx = (c.x - focus.x) * zoom, vy = (c.y - focus.y) * zoom
		let x = 960 + vx * cos(rot) - vy * sin(rot), y = 540 + vx * sin(rot) + vy * cos(rot)
		let s = ws * zoom * k
		if abs(x - 960) > 1440 * s / 2 + 1100 || abs(y - 540) > 900 * s / 2 + 800 { continue }
		let sprite = (i == target && zoom > 2.2) ? MAP_DARK : WALL_SPRITES[i]
		draw(ctx, sprite, Place(x: x, y: y, s: s, rot: rot, alpha: clamp01((t - 23.95 - d * 0.35) / 0.1)), radius: WINDOW_RADIUS, shadow: 0.8)
	}
	let flash = prog(t, 25.82, 26.0)
	if flash > 0 { ctx.setFillColor(hex(0, flash).cg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
}

// MARK: - 8 · 26–30 s: the logo (from the first cut)

func endCard(_ ctx: CGContext, _ t: Double) {
	guard t >= END else { return }
	ctx.setFillColor(hex(0, 1 - prog(t, END, END + 0.8) * 0.3).cg)
	ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
	let sweep = outQuart(prog(t, 26.0, 27.3))
	let glow = 0.35 * clamp01((t - 26.1) / 0.8)
	ctx.drawRadialGradient(gradient([hex(0x7B4DFF, glow), hex(0x2F6BFF, glow * 0.4), hex(0, 0)], [0, 0.5, 1]),
						   startCenter: CGPoint(x: 960, y: 400), startRadius: 0, endCenter: CGPoint(x: 960, y: 400), endRadius: 420, options: [])
	let wave = outExpo(prog(t, END, END + 0.6))
	if wave < 1 {
		ctx.setStrokeColor(hex(0xFFFFFF, 0.5 * (1 - wave)).cg)
		ctx.setLineWidth(3)
		let r = 74 + wave * 900
		ctx.strokeEllipse(in: CGRect(x: 960 - r, y: 400 - r, width: r * 2, height: r * 2))
	}
	drawRing(ctx, cx: 960, cy: 400, r: 74, width: 26, sweep: sweep, rotation: -0.35 * (1 - outQuint(prog(t, 26.0, 27.6))), alpha: prog(t, 25.95, 26.1))
	riseText(ctx, "Diskmap", Style(size: 124, weight: .bold, fill: .color(hex(0xF5F5F7)), kern: -2.5), x: 960, baseline: 640, t: t, start: 26.35)
	riseText(ctx, "Know exactly what’s on your Mac.", Style(size: 42, weight: .semibold, fill: .gradient(BRAND), kern: -0.6), x: 960, baseline: 716, t: t, start: 26.85, stagger: 0.05)
}

// MARK: - Frame

func render(_ ctx: CGContext, _ t: Double) {
	ctx.interpolationQuality = .high
	stage(ctx, t)
	let flashDrop = exp(-max(0, t - DROP) / 0.07) * (t >= DROP ? 1 : 0)
	let sh = shake(t, [DROP, COUNTER, 24.0], amount: 12)
	ctx.saveGState()
	ctx.translateBy(x: sh.x, y: sh.y)
	intro(ctx, t)
	mapScene(ctx, t)
	treemapScene(ctx, t)
	largestScene(ctx, t)
	cleanupScene(ctx, t)
	devTitle(ctx, t)
	devWindow(ctx, t)
	simScene(ctx, t)
	kindsScene(ctx, t)
	lightDark(ctx, t)
	wall(ctx, t)
	ctx.restoreGState()
	endCard(ctx, t)
	drawBurst(ctx, Burst(t: DROP, x: SUN_AT.x, y: SUN_AT.y, colors: [hex(0xC65BF0), hex(0x3B82F6), hex(0x34C759), hex(0xFF453A), hex(0xFFFFFF)], count: 120, speed: 1900, seed: 3), t: t)
	if flashDrop > 0.01 {
		ctx.setFillColor(hex(0xFFFFFF, 0.28 * flashDrop).cg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
	}
	// Fade out the final beat.
	let fade = prog(t, 29.55, 30.0)
	if fade > 0 { ctx.setFillColor(hex(0, fade).cg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
}
