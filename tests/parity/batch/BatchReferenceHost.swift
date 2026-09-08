import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private struct BatchInput: Decodable {
	let schema: Int
	let runId: String
	let cases: [CaseInput]
}

private struct CaseInput: Decodable {
	let id: String
	let width: Double
	let height: Double
	let tree: Node
}

private struct Node: Decodable, Identifiable {
	let id: String
	let kind: Kind
	let text: String?
	let spacing: Double?
	let padding: Double?
	let size: Double?
	let width: Double?
	let height: Double?
	let children: [Node]?

	enum Kind: String, Decodable {
		case text, hstack, vstack, zstack, spacer
	}
}

private struct ProbeValue: Equatable {
	let frame: CGRect
	let text: String?
}

private struct ProbePreferenceKey: PreferenceKey {
	static var defaultValue: [String: ProbeValue] = [:]

	static func reduce(value: inout [String: ProbeValue], nextValue: () -> [String: ProbeValue]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}

private struct ProbedView: View {
	let node: Node

	private var nodeContent: AnyView {
		switch node.kind {
		case .text:
			var value = AnyView(Text(node.text ?? ""))
			if let size = node.size {
				value = AnyView(value.font(.system(size: size)))
			}
			return value
		case .hstack:
			return AnyView(HStack(spacing: node.spacing.map { CGFloat($0) }) {
				ForEach(node.children ?? []) { child in
					ProbedView(node: child)
				}
			})
		case .vstack:
			return AnyView(VStack(spacing: node.spacing.map { CGFloat($0) }) {
				ForEach(node.children ?? []) { child in
					ProbedView(node: child)
				}
			})
		case .zstack:
			return AnyView(ZStack {
				ForEach(node.children ?? []) { child in
					ProbedView(node: child)
				}
			})
		case .spacer:
			return AnyView(Spacer())
		}
	}

	var body: some View {
		var value = AnyView(nodeContent)
		if node.width != nil || node.height != nil {
			let width = node.width.map { CGFloat($0) }
			let height = node.height.map { CGFloat($0) }
			value = AnyView(value.frame(
				width: width,
				height: height
			))
		}
		if let padding = node.padding {
			value = AnyView(value.padding(CGFloat(padding)))
		}
		if node.kind == .spacer {
			return AnyView(value)
		}
		return AnyView(value.background(
			GeometryReader { proxy in
				Color.clear.preference(
					key: ProbePreferenceKey.self,
					value: [node.id: ProbeValue(
						frame: proxy.frame(in: .named("batch-root")),
						text: node.kind == .text ? node.text : nil
					)]
				)
			}
		))
	}
}

private final class ProbeStore: ObservableObject {
	@Published var values: [String: ProbeValue] = [:]
}

private struct CaseView: View {
	let item: CaseInput
	@ObservedObject var store: ProbeStore

	var body: some View {
		ProbedView(node: item.tree)
			.frame(width: item.width, height: item.height)
			.background(.background)
			.coordinateSpace(name: "batch-root")
			.environment(\.locale, Locale.current)
			.environment(\.layoutDirection, .leftToRight)
			.environment(\.dynamicTypeSize, .large)
			.preferredColorScheme(.light)
			.onPreferenceChange(ProbePreferenceKey.self) { store.values = $0 }
	}
}

private struct ProbeOutput: Encodable {
	let id: String
	let x: Double
	let y: Double
	let width: Double
	let height: Double
	let text: String?

	enum CodingKeys: String, CodingKey {
		case id, x, y, width, height, text
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		try container.encode(x, forKey: .x)
		try container.encode(y, forKey: .y)
		try container.encode(width, forKey: .width)
		try container.encode(height, forKey: .height)
		try container.encodeIfPresent(text, forKey: .text)
	}
}

private struct CaseOutput: Encodable {
	let schema: Int
	let runId: String
	let id: String
	let width: Double
	let height: Double
	let platform: String
	let os: String
	let scale: Double
	let appearance: String
	let locale: String
	let textSize: String
	let direction: String
	let coordinateSpace: String
	let probes: [ProbeOutput]
}

private struct DoneOutput: Encodable {
	let runId: String
	let count: Int
}

private struct ErrorOutput: Encodable {
	let runId: String
	let error: String
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	try encoder.encode(value).write(to: url, options: .atomic)
}

private func writeError(_ error: Error, runId: String, outputDirectory: URL) {
	try? writeJSON(ErrorOutput(runId: runId, error: String(describing: error)),
		to: outputDirectory.appendingPathComponent("error.json"))
}

private struct Options {
	let input: URL
	let output: URL
	let writePNG: Bool

	static func parse() throws -> Options {
		let arguments = Array(CommandLine.arguments.dropFirst())
		func value(after flag: String) -> String? {
			guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
				return nil
			}
			return arguments[index + 1]
		}
		guard let input = value(after: "--input"), let output = value(after: "--output") else {
			throw HostError.usage
		}
		guard input.hasPrefix("/"), output.hasPrefix("/") else { throw HostError.usage }
		let known = Set(["--input", input, "--output", output, "--png"])
		guard arguments.allSatisfy(known.contains) else { throw HostError.usage }
		return Options(
			input: URL(fileURLWithPath: input),
			output: URL(fileURLWithPath: output),
			writePNG: arguments.contains("--png")
		)
	}
}

private enum HostError: Error, CustomStringConvertible {
	case usage
	case invalidSchema(Int)
	case duplicateCase(String)
	case duplicateNode(caseID: String, nodeID: String)
	case invalidDimension(String)
	case unstable(String)

	var description: String {
		switch self {
		case .usage:
			return "usage: SwiftUIBatchReference --input INPUT.json --output DIRECTORY [--png]"
		case .invalidSchema(let schema): return "unsupported input schema \(schema); expected 1"
		case .duplicateCase(let id): return "duplicate case id: \(id)"
		case .duplicateNode(let caseID, let nodeID): return "duplicate non-spacer node id in \(caseID): \(nodeID)"
		case .invalidDimension(let message): return message
		case .unstable(let id): return "SwiftUI layout did not stabilize for case: \(id)"
		}
	}
}

#if os(macOS)
private final class BatchRenderer {
	private let application = NSApplication.shared
	private let window: NSWindow

	init() {
		application.setActivationPolicy(.prohibited)
		window = NSWindow(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.backgroundColor = .clear
		window.appearance = NSAppearance(named: .aqua)
	}

	func render(_ item: CaseInput, runId: String, outputDirectory: URL, writePNG: Bool) throws -> CaseOutput {
		let expectedIDs = try validate(item)
		let store = ProbeStore()
		let hosting = NSHostingView(rootView: CaseView(item: item, store: store))
		// These fixtures measure a content viewport, not device safe-area chrome.
		hosting.safeAreaRegions = []
		let size = NSSize(width: item.width, height: item.height)
		hosting.frame = NSRect(origin: .zero, size: size)
		window.setContentSize(size)
		window.contentView = hosting
		window.orderFrontRegardless()

		var previous: [String: ProbeValue]?
		var stablePasses = 0
		let deadline = Date().addingTimeInterval(5)
		repeat {
			hosting.needsLayout = true
			hosting.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date().addingTimeInterval(0.01))
			let current = store.values
			if Set(current.keys) == expectedIDs, current == previous {
				stablePasses += 1
			} else {
				stablePasses = 0
			}
			previous = current
		} while stablePasses < 3 && Date() < deadline

		guard stablePasses >= 3, let values = previous else { throw HostError.unstable(item.id) }
		let scale = window.backingScaleFactor
		let probes = values.keys.sorted().compactMap { id -> ProbeOutput? in
			guard let value = values[id] else { return nil }
			return ProbeOutput(
				id: id,
				x: value.frame.minX,
				y: value.frame.minY,
				width: value.frame.width,
				height: value.frame.height,
				text: value.text
			)
		}
		if writePNG {
			try capture(hosting, to: outputDirectory.appendingPathComponent("\(item.id).png"), scale: scale)
		}
		window.orderOut(nil)
		return CaseOutput(
			schema: 1,
			runId: runId,
			id: item.id,
			width: item.width,
			height: item.height,
			platform: "macos",
			os: ProcessInfo.processInfo.operatingSystemVersionString,
			scale: scale,
			appearance: "light",
			locale: Locale.current.identifier,
			textSize: "large",
			direction: "ltr",
			coordinateSpace: "root-top-left-points",
			probes: probes
		)
	}

	private func validate(_ item: CaseInput) throws -> Set<String> {
		guard item.width.isFinite, item.height.isFinite, item.width > 0, item.height > 0 else {
			throw HostError.invalidDimension("case \(item.id) requires finite positive width and height")
		}
		var ids = Set<String>()
		var semanticIDs = Set<String>()
		func visit(_ node: Node) throws {
			for value in [node.spacing, node.padding, node.size, node.width, node.height].compactMap({ $0 }) {
				guard value.isFinite, value >= 0 else {
					throw HostError.invalidDimension("node \(node.id) in \(item.id) has a non-finite or negative numeric value")
				}
			}
			guard semanticIDs.insert(node.id).inserted else {
				throw HostError.duplicateNode(caseID: item.id, nodeID: node.id)
			}
			if node.kind != .spacer { ids.insert(node.id) }
			for child in node.children ?? [] { try visit(child) }
		}
		try visit(item.tree)
		return ids
	}

	private func capture(_ view: NSView, to url: URL, scale _: CGFloat) throws {
		guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
			throw HostError.invalidDimension("could not allocate PNG bitmap")
		}
		representation.size = view.bounds.size
		view.cacheDisplay(in: view.bounds, to: representation)
		guard let data = representation.representation(using: .png, properties: [:]) else {
			throw HostError.invalidDimension("could not encode PNG")
		}
		try data.write(to: url, options: .atomic)
	}
}

@main
private enum BatchReferenceHost {
	static func main() {
		do {
			let options = try Options.parse()
			let data = try Data(contentsOf: options.input)
			let input = try JSONDecoder().decode(BatchInput.self, from: data)
			guard input.schema == 1 else { throw HostError.invalidSchema(input.schema) }
			try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
			var caseIDs = Set<String>()
			guard input.cases.allSatisfy({ caseIDs.insert($0.id).inserted }) else {
				throw HostError.duplicateCase(input.cases.first { item in
					input.cases.filter { $0.id == item.id }.count > 1
				}?.id ?? "unknown")
			}
			let renderer = BatchRenderer()
			do {
				for item in input.cases {
					let result = try renderer.render(
						item,
						runId: input.runId,
						outputDirectory: options.output,
						writePNG: options.writePNG
					)
					try writeJSON(result, to: options.output.appendingPathComponent("\(item.id).json"))
				}
				try writeJSON(DoneOutput(runId: input.runId, count: input.cases.count),
					to: options.output.appendingPathComponent("done.json"))
			} catch {
				writeError(error, runId: input.runId, outputDirectory: options.output)
				throw error
			}
		} catch {
			FileHandle.standardError.write(Data("batch reference failed: \(error)\n".utf8))
			exit(error is HostError ? 2 : 1)
		}
	}
}
#elseif os(iOS)
private final class BatchRenderer {
	private let window: UIWindow
	private let container = UIViewController()
	private var hosting: UIViewController?

	init(window: UIWindow) {
		self.window = window
		window.rootViewController = container
		window.overrideUserInterfaceStyle = .light
		window.makeKeyAndVisible()
	}

	func render(_ item: CaseInput, runId: String, outputDirectory: URL, writePNG: Bool) throws -> CaseOutput {
		let expectedIDs = try validate(item)
		hosting?.willMove(toParent: nil)
		hosting?.view.removeFromSuperview()
		hosting?.removeFromParent()

		let store = ProbeStore()
		let controller = UIHostingController(rootView: CaseView(item: item, store: store))
		controller.safeAreaRegions = []
		container.addChild(controller)
		controller.view.frame = CGRect(x: 0, y: 0, width: item.width, height: item.height)
		controller.view.backgroundColor = .clear
		container.view.addSubview(controller.view)
		controller.didMove(toParent: container)
		hosting = controller

		var previous: [String: ProbeValue]?
		var stablePasses = 0
		let deadline = Date().addingTimeInterval(5)
		repeat {
			controller.view.setNeedsLayout()
			controller.view.layoutIfNeeded()
			RunLoop.main.run(until: Date().addingTimeInterval(0.01))
			let current = store.values
			if Set(current.keys) == expectedIDs, current == previous {
				stablePasses += 1
			} else {
				stablePasses = 0
			}
			previous = current
		} while stablePasses < 3 && Date() < deadline

		guard stablePasses >= 3, let values = previous else { throw HostError.unstable(item.id) }
		let scale = window.screen.scale
		let probes = values.keys.sorted().compactMap { id -> ProbeOutput? in
			guard let value = values[id] else { return nil }
			return ProbeOutput(
				id: id,
				x: value.frame.minX,
				y: value.frame.minY,
				width: value.frame.width,
				height: value.frame.height,
				text: value.text
			)
		}
		if writePNG {
			try capture(controller.view, to: outputDirectory.appendingPathComponent("\(item.id).png"), scale: scale)
		}
		return CaseOutput(
			schema: 1,
			runId: runId,
			id: item.id,
			width: item.width,
			height: item.height,
			platform: "ios",
			os: ProcessInfo.processInfo.operatingSystemVersionString,
			scale: scale,
			appearance: "light",
			locale: Locale.current.identifier,
			textSize: "large",
			direction: "ltr",
			coordinateSpace: "root-top-left-points",
			probes: probes
		)
	}

	private func validate(_ item: CaseInput) throws -> Set<String> {
		guard item.width.isFinite, item.height.isFinite, item.width > 0, item.height > 0 else {
			throw HostError.invalidDimension("case \(item.id) requires finite positive width and height")
		}
		var ids = Set<String>()
		var semanticIDs = Set<String>()
		func visit(_ node: Node) throws {
			for value in [node.spacing, node.padding, node.size, node.width, node.height].compactMap({ $0 }) {
				guard value.isFinite, value >= 0 else {
					throw HostError.invalidDimension("node \(node.id) in \(item.id) has a non-finite or negative numeric value")
				}
			}
			guard semanticIDs.insert(node.id).inserted else {
				throw HostError.duplicateNode(caseID: item.id, nodeID: node.id)
			}
			if node.kind != .spacer { ids.insert(node.id) }
			for child in node.children ?? [] { try visit(child) }
		}
		try visit(item.tree)
		return ids
	}

	private func capture(_ view: UIView, to url: URL, scale: CGFloat) throws {
		let format = UIGraphicsImageRendererFormat()
		format.scale = scale
		format.opaque = false
		let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
			view.layer.render(in: context.cgContext)
		}
		guard let data = image.pngData() else {
			throw HostError.invalidDimension("could not encode PNG")
		}
		try data.write(to: url, options: .atomic)
	}
}

@main
private final class BatchReferenceAppDelegate: UIResponder, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		configurationForConnecting connectingSceneSession: UISceneSession,
		options: UIScene.ConnectionOptions
	) -> UISceneConfiguration {
		let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
		configuration.delegateClass = BatchReferenceSceneDelegate.self
		return configuration
	}
}

private final class BatchReferenceSceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		guard let windowScene = scene as? UIWindowScene else { return }
		let window = UIWindow(windowScene: windowScene)
		self.window = window
		DispatchQueue.main.async { self.run(window: window) }
	}

	private func run(window: UIWindow) {
		do {
			let options = try Options.parse()
			let data = try Data(contentsOf: options.input)
			let input = try JSONDecoder().decode(BatchInput.self, from: data)
			guard input.schema == 1 else { throw HostError.invalidSchema(input.schema) }
			try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
			var caseIDs = Set<String>()
			guard input.cases.allSatisfy({ caseIDs.insert($0.id).inserted }) else {
				throw HostError.duplicateCase(input.cases.first { item in
					input.cases.filter { $0.id == item.id }.count > 1
				}?.id ?? "unknown")
			}
			let renderer = BatchRenderer(window: window)
			do {
				for item in input.cases {
					let result = try renderer.render(
						item,
						runId: input.runId,
						outputDirectory: options.output,
						writePNG: options.writePNG
					)
					try writeJSON(result, to: options.output.appendingPathComponent("\(item.id).json"))
				}
				try writeJSON(DoneOutput(runId: input.runId, count: input.cases.count),
					to: options.output.appendingPathComponent("done.json"))
			} catch {
				writeError(error, runId: input.runId, outputDirectory: options.output)
				throw error
			}
			exit(0)
		} catch {
			FileHandle.standardError.write(Data("batch reference failed: \(error)\n".utf8))
			exit(error is HostError ? 2 : 1)
		}
	}
}
#endif
