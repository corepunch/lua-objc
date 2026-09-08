import AppKit
import SwiftUI

private enum Fixture: String {
	case text = "text.single.default"
	case stack = "stack.h.spacing.default-text-spacer"
	case button = "button.standard.action-counter"
	case surface = "surface.background-rounded"
	case grid = "grid.two-by-two"
	case longText = "text.long-ellipsis-italic"
	case image = "image.system-icon"
	case padding = "padding.vertical-edges"
	case container = "container.section-groupbox"

	var sceneName: String {
		switch self {
		case .text: return "TextScene"
		case .stack: return "HStackScene"
		case .button: return "ButtonScene"
		case .surface: return "SurfaceScene"
		case .grid: return "GridScene"
		case .longText: return "LongTextScene"
		case .image: return "ImageScene"
		case .padding: return "PaddingScene"
		case .container: return "ContainerScene"
		}
	}

	var size: CGSize {
		switch self {
		case .text, .button, .surface, .grid, .longText, .image, .padding: return CGSize(width: 320, height: 120)
		case .container: return CGSize(width: 320, height: 160)
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
		case .surface:
			ProbeView(id: "surface", content: Text("Native rounded surface")
				.padding(24)
				.frame(maxWidth: .infinity)
				.background(Color.green)
				.clipShape(RoundedRectangle(cornerRadius: 16)))
		case .grid:
			Grid(horizontalSpacing: 24, verticalSpacing: 12) {
				GridRow {
					ProbeView(id: "A1", content: Text("A1"))
					ProbeView(id: "B1", content: Text("B1"))
				}
				GridRow {
					ProbeView(id: "A2", content: Text("A2"))
					ProbeView(id: "B2", content: Text("B2"))
				}
			}
		case .longText:
			ProbeView(id: "styled", content: Text("A deliberately long semantic text value that must truncate at the trailing edge")
				.font(.system(size: 18)).italic().lineLimit(1).truncationMode(.tail)
				.multilineTextAlignment(.center))
		case .image:
			ProbeView(id: "icon", content: Image(systemName: "star.fill")
				.font(.system(size: 32)).foregroundStyle(.tint)
				.accessibilityLabel("Favorite"))
		case .padding:
			ProbeView(id: "padded", content: Text("Top and bottom edges")
				.padding(.top, 8).padding(.bottom, 40)
				.frame(maxWidth: .infinity).background(Color.green)
				.clipShape(RoundedRectangle(cornerRadius: 12)))
		case .container:
			VStack(alignment: .leading, spacing: 12) {
				ProbeView(id: "section", content: VStack(alignment: .leading, spacing: 8) {
					Text("Overview").bold()
					Text("Nested native content")
				})
				ProbeView(id: "groupbox", content: VStack(alignment: .leading, spacing: 8) {
					Text("Details").bold()
					Text("Grouped native content")
				}.padding(12).background(Color.green).clipShape(RoundedRectangle(cornerRadius: 12)))
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
