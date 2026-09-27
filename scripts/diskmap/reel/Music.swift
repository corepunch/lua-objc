// The score, generated from the storyboard's own event lists at 120 BPM.
// B minor build → drop on D at 4 s → breakdown at 20 s → final lift at 24 s
// → D major landing on the logo at 26 s.
import Foundation

func midiHz(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

struct Chord { let root: Double; let pad: [Double] }
let BM = Chord(root: 47, pad: [54, 59, 62, 66, 69]), G = Chord(root: 43, pad: [55, 59, 62, 66, 71])
let D = Chord(root: 38, pad: [57, 62, 64, 66, 69]), A = Chord(root: 45, pad: [57, 61, 64, 69, 71])
let EM = Chord(root: 40, pad: [55, 59, 62, 64, 67])
let BARS: [Chord] = [BM, G, D, A, BM, G, D, A, BM, G, EM, A, BM, D, D]
func chord(_ t: Double) -> Chord { BARS[min(BARS.count - 1, max(0, Int(t / BAR)))] }

final class Mix {
	let n: Int, sr: Double
	var dryL: [Double], dryR: [Double], sendL: [Double], sendR: [Double], duckL: [Double], duckR: [Double]
	var seed: UInt32 = 12345
	init(duration: Double, sr: Double) {
		self.sr = sr; n = Int(duration * sr)
		dryL = [Double](repeating: 0, count: n); dryR = dryL; sendL = dryL; sendR = dryL; duckL = dryL; duckR = dryL
	}
	func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / Double(UInt32.max) * 2 - 1 }
	func range(_ t0: Double, _ dur: Double) -> Range<Int> {
		let a = max(0, Int(t0 * sr)), b = min(n, Int((t0 + dur) * sr))
		return a..<max(a, b)
	}
	func add(_ i: Int, _ v: Double, pan: Double = 0.5, send: Double = 0, duck: Bool = false) {
		let l = v * (1 - pan) * 2, r = v * pan * 2
		if duck { duckL[i] += l; duckR[i] += r } else { dryL[i] += l; dryR[i] += r }
		sendL[i] += l * send; sendR[i] += r * send
	}
}

func synthesize(duration: Double, sr: Double) -> ([Float], [Float]) {
	let m = Mix(duration: duration, sr: sr)
	func section(_ t: Double) -> String {
		if t < 4 { return "intro" }
		if t < 20 { return "drop" }
		if t < 24 { return "break" }
		if t < 26 { return "lift" }
		return "end"
	}

	// Pad: detuned additive saws, one voicing per bar with crossfades.
	for (b, c) in BARS.enumerated() {
		let t0 = Double(b) * BAR, len = BAR + 0.6
		let last = b == BARS.count - 1 || b == BARS.count - 2
		for i in m.range(t0, last ? duration - t0 : len) {
			let t = Double(i) / sr, local = t - t0
			var env = min(1, local / 0.12)
			if !last && local > BAR { env *= max(0, 1 - (local - BAR) / 0.6) }
			if b == 13 { env *= 1 } // lands and rings through the end card
			let level: Double = [ "intro": 0.9, "drop": 0.5, "break": 0.95, "lift": 0.6, "end": 1.05 ][section(t)]!
			let bright = section(t) == "intro" ? 0.35 + 0.5 * t / 4 : 1
			var l = 0.0, r = 0.0
			for note in c.pad {
				for (cents, pl) in [(-8.0, 0.8), (0.0, 0.5), (8.0, 0.2)] {
					let f = midiHz(note + cents / 100)
					var v = 0.0
					for k in 1...6 { v += sin(2 * .pi * f * Double(k) * t + Double(k)) / pow(Double(k), 2.3 - 0.9 * bright) }
					l += v * pl; r += v * (1 - pl)
				}
			}
			let g = 0.011 * env * level
			m.duckL[i] += l * g; m.duckR[i] += r * g
			m.sendL[i] += l * g * 0.7; m.sendR[i] += r * g * 0.7
		}
	}

	// Plucked arpeggio: 8ths in the intro and breakdown, 16ths in the drops.
	let pattern = [0, 2, 4, 1, 3, 4, 2, 1]
	var step = 0
	var at = 0.0
	while at < 26.0 {
		let t = at
		let sec = section(t)
		let stepLen = (sec == "intro" || sec == "break") ? BEAT / 2 : BEAT / 4
		let c = chord(t)
		let note = c.pad[pattern[step % pattern.count] % c.pad.count] + 12
		let f = midiHz(note)
		let accent = step % 4 == 0 ? 1.0 : (step % 2 == 0 ? 0.8 : 0.62)
		let base: Double = ["intro": 0.05 + 0.03 * t / 4, "drop": 0.05, "break": 0.06, "lift": 0.065][sec] ?? 0.05
		let bright = sec == "intro" ? 0.2 + 0.8 * t / 4 : 1
		let pan = step % 2 == 0 ? 0.32 : 0.68
		for i in m.range(t, 0.9) {
			let dt = Double(i) / sr - t
			let env = exp(-dt / 0.16) * (1 - exp(-dt / 0.002))
			let ph = 2 * .pi * f * dt
			let v = (sin(ph) + 0.45 * bright * sin(2 * ph) * exp(-dt / 0.07) + 0.2 * bright * sin(3 * ph) * exp(-dt / 0.04)) * env * base * accent
			m.add(i, v, pan: pan, send: 0.5, duck: true)
		}
		step += 1
		at += stepLen
	}

	// Bass: pumping 8ths in the drops, long notes in the breakdown.
	for b in 2..<13 {
		let c = BARS[b], t0 = Double(b) * BAR
		let sec = section(t0)
		if sec == "break" {
			for half in 0..<2 {
				let st = t0 + Double(half) * BAR / 2
				for i in m.range(st, BAR / 2) {
					let dt = Double(i) / sr - st, f = midiHz(c.root)
					let env = min(1, dt / 0.02) * exp(-dt / 1.4)
					m.add(i, (sin(2 * .pi * f * dt) + 0.3 * sin(4 * .pi * f * dt)) * env * 0.16, duck: true)
				}
			}
			continue
		}
		for e in 0..<8 {
			let st = t0 + Double(e) * BEAT / 2
			let note = c.root + (e % 4 == 3 ? 12 : 0)
			let f = midiHz(note)
			for i in m.range(st, BEAT / 2 - 0.01) {
				let dt = Double(i) / sr - st
				let env = min(1, dt / 0.004) * exp(-dt / 0.35)
				var v = 0.0
				for k in 1...5 { v += sin(2 * .pi * f * Double(k) * dt) / Double(k * k) }
				m.add(i, v * env * 0.2, duck: true)
			}
		}
	}

	// Drums.
	for k in KICKS {
		var phase = 0.0
		for i in m.range(k, 0.45) {
			let dt = Double(i) / sr - k
			phase += 2 * .pi * (46 + 120 * exp(-dt / 0.03)) / sr
			let click = dt < 0.004 ? m.noise() * 0.25 * (1 - dt / 0.004) : 0
			m.add(i, (sin(phase) * exp(-dt / 0.26) * 0.62 + click))
		}
	}
	var claps: [Double] = []
	for b in 2..<13 where section(Double(b) * BAR) != "break" { claps += [Double(b) * BAR + 0.5, Double(b) * BAR + 1.5] }
	claps += [21.0, 23.0]
	for c in claps {
		var prev = 0.0
		for i in m.range(c, 0.3) {
			let dt = Double(i) / sr - c
			let bursts = [0.0, 0.011, 0.022].reduce(0.0) { acc, o in acc + (dt >= o ? exp(-(dt - o) / (o == 0.022 ? 0.09 : 0.008)) : 0) }
			let x = m.noise(); let h = x - prev; prev = x
			m.add(i, h * bursts * 0.16, pan: 0.52, send: 0.6)
		}
	}
	for b in 2..<13 where section(Double(b) * BAR) != "break" {
		for s in 0..<16 {
			let st = Double(b) * BAR + Double(s) * BEAT / 4
			let open = s % 4 == 2
			if !open && b < 4 { continue }
			var p1 = 0.0, p2 = 0.0
			let len = open ? 0.2 : 0.05
			for i in m.range(st, len) {
				let dt = Double(i) / sr - st
				let x = m.noise(); let h1 = x - p1; p1 = x; let h2 = h1 - p2; p2 = h1
				let lvl = open ? 0.05 : (s % 2 == 1 ? 0.035 : 0.022)
				m.add(i, h2 * exp(-dt / (open ? 0.07 : 0.015)) * lvl, pan: open ? 0.62 : 0.4)
			}
		}
	}
	for c in CRASHES {
		var p1 = 0.0
		let big = c == DROP || c == END
		for i in m.range(c, big ? 2.4 : 1.6) {
			let dt = Double(i) / sr - c
			let x = m.noise(); let h = x - p1; p1 = x
			m.add(i, h * exp(-dt / (big ? 0.9 : 0.55)) * (big ? 0.11 : 0.07), pan: 0.5, send: 0.4)
		}
	}
	for (a, b) in ROLLS {
		var hit = a
		while hit < b {
			let x = prog(hit, a, b)
			var p1 = 0.0
			for i in m.range(hit, 0.08) {
				let dt = Double(i) / sr - hit
				let nz = m.noise(); let h = nz - p1; p1 = nz
				let v = (h * 0.8 + sin(2 * .pi * 190 * dt) * 0.4) * exp(-dt / 0.03) * (0.03 + 0.12 * x * x)
				m.add(i, v, pan: 0.5, send: 0.3)
			}
			hit += mix(0.125, 0.031, x)
		}
	}

	// Risers, whooshes and the drop gap.
	for (a, b) in RISERS {
		var lp = 0.0, phase = 0.0
		for i in m.range(a, b - a) {
			let x = prog(Double(i) / sr, a, b)
			lp += (m.noise() - lp) * (0.01 + 0.35 * x * x)
			phase += 2 * .pi * (180 * pow(8, x)) / sr
			m.add(i, (lp * 0.2 + sin(phase) * 0.03) * pow(x, 2.2), pan: 0.5, send: 0.5)
		}
	}
	for (a, b) in WHOOSHES + DIVIDER_MOVES.map({ ($0 - 0.02, $0 + 0.3) }) {
		var lp = 0.0
		for i in m.range(a, b - a + 0.15) {
			let x = prog(Double(i) / sr, a, b + 0.15)
			let bell = sin(.pi * x)
			lp += (m.noise() - lp) * (0.04 + 0.4 * bell)
			m.add(i, lp * bell * bell * 0.22, pan: 0.15 + 0.7 * x, send: 0.35)
		}
	}

	// Slams: a thump with a click; the drop and the logo get a sub boom.
	for s in SLAMS {
		var phase = 0.0
		for i in m.range(s, 0.35) {
			let dt = Double(i) / sr - s
			phase += 2 * .pi * (70 + 160 * exp(-dt / 0.02)) / sr
			let click = dt < 0.006 ? m.noise() * 0.35 * (1 - dt / 0.006) : 0
			m.add(i, sin(phase) * exp(-dt / 0.14) * 0.42 + click, send: 0.2)
		}
	}
	for boom in [DROP, END, WALL] {
		var phase = 0.0
		for i in m.range(boom, 1.6) {
			let dt = Double(i) / sr - boom
			phase += 2 * .pi * (34 + 70 * exp(-dt / 0.06)) / sr
			m.add(i, sin(phase) * exp(-dt / (boom == WALL ? 0.4 : 0.9)) * 0.7)
		}
	}

	// UI pops, pitched to the chord so the cascades sing.
	for (j, p) in POPS.sorted().enumerated() {
		let c = chord(p)
		let note = c.pad[j % c.pad.count] + 24
		let f = midiHz(note)
		for i in m.range(p, 0.18) {
			let dt = Double(i) / sr - p
			let ff = f * (1 + 0.6 * exp(-dt / 0.012))
			let v = sin(2 * .pi * ff * dt) * exp(-dt / 0.05) * 0.075
			m.add(i, v, pan: 0.3 + 0.4 * Double(j % 3) / 2, send: 0.35)
		}
	}
	// The counter: a bright run up the chord.
	for (j, note) in [74.0, 78, 81, 86, 90].enumerated() {
		let st = COUNTER + Double(j) * 0.045
		for i in m.range(st, 0.8) {
			let dt = Double(i) / sr - st
			m.add(i, sin(2 * .pi * midiHz(note) * dt) * exp(-dt / 0.3) * 0.05, pan: 0.3 + 0.1 * Double(j), send: 0.6)
		}
	}
	// The logo: a bell chord, arpeggiated.
	for (j, note) in [74.0, 78, 81, 88, 90].enumerated() {
		let st = END + Double(j) * 0.11
		for i in m.range(st, duration - st) {
			let dt = Double(i) / sr - st
			let f = midiHz(note)
			let env = exp(-dt / 2.6) * (1 - exp(-dt / 0.002))
			let v = (sin(2 * .pi * f * dt) + 0.3 * sin(2 * .pi * f * 2.76 * dt) * exp(-dt / 0.35)) * env * 0.055
			m.add(i, v, pan: [0.5, 0.3, 0.7, 0.4, 0.6][j], send: 0.8)
		}
	}

	// Sidechain, reverb, master.
	var lastKick = -10.0
	var k = 0
	let kicks = KICKS.sorted()
	for i in 0..<m.n {
		let t = Double(i) / sr
		while k < kicks.count && kicks[k] <= t { lastKick = kicks[k]; k += 1 }
		let duck = 1 - 0.6 * exp(-(t - lastKick) / 0.11)
		m.dryL[i] += m.duckL[i] * duck; m.dryR[i] += m.duckR[i] * duck
	}
	func reverb(_ input: [Double], spread: Int) -> [Double] {
		let scale = sr / 44100
		var combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116].map { [Double](repeating: 0, count: Int(Double($0 + spread) * scale)) }
		var ci = [Int](repeating: 0, count: combs.count), store = [Double](repeating: 0, count: combs.count)
		var alls = [556, 441, 341, 225].map { [Double](repeating: 0, count: Int(Double($0 + spread) * scale)) }
		var ai = [Int](repeating: 0, count: alls.count)
		var out = [Double](repeating: 0, count: input.count)
		for i in 0..<input.count {
			let x = input[i] * 0.015
			var y = 0.0
			for c in 0..<combs.count {
				let o = combs[c][ci[c]]
				y += o
				store[c] = o * 0.72 + store[c] * 0.28
				combs[c][ci[c]] = x + store[c] * 0.85
				ci[c] = (ci[c] + 1) % combs[c].count
			}
			for a in 0..<alls.count {
				let o = alls[a][ai[a]]
				let v = -y + o
				alls[a][ai[a]] = y + o * 0.5
				ai[a] = (ai[a] + 1) % alls[a].count
				y = v
			}
			out[i] = y
		}
		return out
	}
	let rl = reverb(m.sendL, spread: 0), rr = reverb(m.sendR, spread: 23)
	var left = [Float](repeating: 0, count: m.n), right = left
	var outL = [Double](repeating: 0, count: m.n), outR = outL
	var peak = 0.0
	for i in 0..<m.n {
		let t = Double(i) / sr
		var g = min(1, t / 0.02)
		if t >= 3.94 && t < DROP { g *= 0.08 }   // a breath before the drop
		if t > 29.2 { g *= 0.5 + 0.5 * cos(.pi * min(1, (t - 29.2) / 0.8)) }
		outL[i] = tanh(1.25 * (m.dryL[i] + rl[i] * 0.8)) * g
		outR[i] = tanh(1.25 * (m.dryR[i] + rr[i] * 0.8)) * g
		peak = max(peak, abs(outL[i]), abs(outR[i]))
	}
	let gain = 0.89 / peak
	var sum = 0.0
	for i in 0..<m.n {
		left[i] = Float(outL[i] * gain); right[i] = Float(outR[i] * gain)
		sum += Double(left[i] * left[i])
	}
	print(String(format: "audio: gain %.2f, RMS %.1f dBFS", gain, 10 * log10(sum / Double(m.n))))
	return (left, right)
}
