import AppKit
import SwiftUI

private enum Fixture: String {
	case text = "text.single.default"
	case stack = "stack.h.spacing.default-text-spacer"
	case button = "button.standard.action-counter"

	var sceneName: String {
		switch self {
		case .text: return "TextScene"
		case .stack: return "HStackScene"
		case .button: return "ButtonScene"
		}
	}

	var size: CGSize {
		switch self {
		case .text, .button: return CGSize(width: 320, height: 120)
		case .stack: return CGSize(width: 480, height: 120)
		}
	}
}

private struct Probe: Codable {
	let id: String
	let x: Double
	let y: Double
	let width: Double
	let height: Double
}

private struct Readiness: Codable {
	let schema: Int
	let host: String
	let fixture: String
	let scene: String
	let generation: String
	let actionCount: Int
	let probes: [Probe]
}

private struct ProbePreferenceKey: PreferenceKey {
	static var defaultValue: [String: CGRect] = [:]

	static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}

private struct ProbeView<Content: View>: View {
	let id: String
	let content: Content

	var body: some View {
		content.background(
			GeometryReader { proxy in
				Color.clear.preference(
					key: ProbePreferenceKey.self,
					value: [id: proxy.frame(in: .named("parity"))]
				)
			}
		)
	}
}

private struct FixtureView: View {
	let fixture: Fixture
	let activateOnLaunch: Bool
	let writeReadiness: ([String: CGRect], Int) -> Void
	@State private var actionCount = 0

	private func activate() {
		actionCount += 1
	}

	@ViewBuilder
	private var content: some View {
		switch fixture {
		case .text:
			ProbeView(id: "text.node", content: Text("Parity text"))
		case .stack:
			HStack {
				ProbeView(id: "left", content: Text("Left"))
				Spacer()
				ProbeView(id: "right", content: Text("Right"))
			}
		case .button:
			VStack(spacing: 12) {
				ProbeView(id: "button", content: Button("Activate", action: activate))
				ProbeView(id: "counter", content: Text("Count: \(actionCount)"))
			}
		}
	}

	var body: some View {
		content
			.padding(20)
			.frame(width: fixture.size.width, height: fixture.size.height)
			.coordinateSpace(name: "parity")
			.onPreferenceChange(ProbePreferenceKey.self) { probes in
				writeReadiness(probes, actionCount)
			}
			.task {
				if activateOnLaunch && fixture == .button {
					try? await Task.sleep(for: .milliseconds(150))
					activate()
				}
			}
	}
}

@main
struct ReferenceHost: App {
	private let fixture: Fixture
	private let readyPath: String
	private let generation: String
	private let activateOnLaunch: Bool

	init() {
		let arguments = CommandLine.arguments
		func value(_ name: String) -> String? {
			guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
				return nil
			}
			return arguments[index + 1]
		}

		guard let rawFixture = value("--case"), let fixture = Fixture(rawValue: rawFixture) else {
			fatalError("missing or unsupported --case; expected one of the parity manifest IDs")
		}
		self.fixture = fixture
		self.readyPath = value("--ready-file") ?? "/tmp/lua-objc-swiftui-reference.json"
		self.generation = value("--generation") ?? UUID().uuidString
		self.activateOnLaunch = arguments.contains("--activate")
	}

	private func writeReadiness(probes: [String: CGRect], actionCount: Int) {
		let payload = Readiness(
			schema: 1,
			host: "swiftui-macos",
			fixture: fixture.rawValue,
			scene: fixture.sceneName,
			generation: generation,
			actionCount: actionCount,
			probes: probes.keys.sorted().compactMap { id in
				guard let frame = probes[id] else { return nil }
				return Probe(id: id, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
			}
		)
		guard let data = try? JSONEncoder().encode(payload) else { return }
		try? data.write(to: URL(fileURLWithPath: readyPath), options: .atomic)
	}

	var body: some Scene {
		WindowGroup(fixture.sceneName) {
			FixtureView(fixture: fixture, activateOnLaunch: activateOnLaunch, writeReadiness: writeReadiness)
		}
		.defaultSize(width: fixture.size.width, height: fixture.size.height)
		.windowResizability(.contentSize)
	}
}
