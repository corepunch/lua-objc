import Foundation
import SwiftUI

private struct Contract: Decodable {
	let schema: Int
	let environment: Environment
	let layout: Layout
	let screens: [Screen]
}

private struct Environment: Decodable {
	let device: String
	let runtime: String
	let appearance: String
	let locale: String
	let layoutDirection: String
	let dynamicType: String
	let statusBarTime: String
}

private struct Layout: Decodable {
	let horizontalInset: CGFloat
	let stackSpacing: CGFloat
	let sectionSpacing: CGFloat
	let sampleSpacing: CGFloat
	let buttonSpacing: CGFloat
	let nestedSpacing: CGFloat
	let horizontalSpacing: CGFloat
	let controlSpacing: CGFloat
	let sliderRowSpacing: CGFloat
	let progressSpacing: CGFloat
	let overlaySize: CGFloat
	let gridSpacing: CGFloat
	let gridCellSpacing: CGFloat
	let stackRowSpacing: CGFloat
}

private struct Screen: Decodable, Identifiable {
	let id: String
	let title: String
	let samples: [Sample]?
	let systemLabel: SystemLabel?
	let buttons: [Sample]?
	let leading: String?
	let trailing: String?
	let nestedTitle: String?
	let nestedSubtitle: String?
	let overlaySymbol: String?
	let field: Field?
	let toggle: ToggleFixture?
	let slider: SliderFixture?
	let progress: ProgressFixture?
	let toggles: [ToggleFixture]?
	let tabs: [TabFixture]?
	let selectedIndex: Int?
	let grid: [[Sample]]?
	let quickConditions: [ConditionFixture]?
}

private struct Sample: Decodable, Identifiable {
	let id: String
	let text: String?
	let title: String?
	let size: CGFloat?
	let weight: String?
	let color: String?
	let lines: Int?
	let style: String?
	let symbol: String?
	let disabled: Bool?
	let role: String?
	let accessibilityLabel: String?
}

private struct SystemLabel: Decodable {
	let id: String
	let title: String
	let symbol: String
}

private struct Field: Decodable {
	let label: String
	let placeholder: String
	let value: String
}

private struct ToggleFixture: Decodable {
	let label: String
	let value: Bool
	let disabled: Bool?
}

private struct TabFixture: Decodable, Identifiable {
	let id: String
	let title: String
	let symbol: String
	let heading: String
	let subtitle: String
	let detail: String
}

private struct ConditionFixture: Decodable, Identifiable {
	let id: String
	let title: String
	let value: String
}

private struct SliderFixture: Decodable {
	let label: String
	let min: Double
	let max: Double
	let value: Double
}

private struct ProgressFixture: Decodable {
	let label: String
	let value: Double
}

private enum ComparisonError: Error {
	case missingContract
	case unsupportedSchema(Int)
	case missingScreen(String)
}

private func loadContract() throws -> Contract {
	guard let url = Bundle.main.url(forResource: "contract", withExtension: "json") else {
		throw ComparisonError.missingContract
	}
	let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: url))
	guard contract.schema == 1 else { throw ComparisonError.unsupportedSchema(contract.schema) }
	return contract
}

private func selectedScreen(in contract: Contract) throws -> Screen {
	let fixtureID = ProcessInfo.processInfo.environment["SWIFTUI_COMPARISON_FIXTURE"] ?? "labels"
	guard let screen = contract.screens.first(where: { $0.id == fixtureID }) else {
		throw ComparisonError.missingScreen(fixtureID)
	}
	return screen
}

private func fontWeight(_ value: String?) -> Font.Weight {
	switch value ?? "regular" {
	case "ultraLight": return .ultraLight
	case "thin": return .thin
	case "light": return .light
	case "medium": return .medium
	case "semibold": return .semibold
	case "bold": return .bold
	case "heavy": return .heavy
	case "black": return .black
	default: return .regular
	}
}

private func sampleFont(_ sample: Sample) -> Font {
	.system(size: sample.size ?? 16, weight: fontWeight(sample.weight))
}

private struct ComparisonView: View {
	let contract: Contract
	let screen: Screen
	@State private var selectedTab: Int

	init(contract: Contract, screen: Screen) {
		self.contract = contract
		self.screen = screen
		_selectedTab = State(initialValue: screen.selectedIndex ?? 0)
	}

	@ViewBuilder
	private var fixtureContent: some View {
		switch screen.id {
		case "labels":
			VStack(alignment: .leading, spacing: contract.layout.sectionSpacing) {
				ForEach(screen.samples ?? []) { sample in
					Text(sample.text ?? "")
						.font(sampleFont(sample))
						.foregroundStyle(sample.color == "secondary" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
						.lineLimit(sample.lines)
				}
				if let label = screen.systemLabel {
					Label(label.title, systemImage: label.symbol)
						.font(.system(size: 16))
				}
			}
		case "buttons":
			VStack(alignment: .leading, spacing: contract.layout.buttonSpacing) {
				ForEach(screen.buttons ?? []) { button in
					buttonView(button)
				}
			}
		case "toggles":
			VStack(alignment: .leading, spacing: contract.layout.controlSpacing) {
				ForEach(Array((screen.toggles ?? []).enumerated()), id: \.offset) { item in
					let toggle = item.element
					Toggle(toggle.label, isOn: .constant(toggle.value))
						.disabled(toggle.disabled ?? false)
				}
			}
		case "grid":
			Grid(horizontalSpacing: contract.layout.gridSpacing,
				verticalSpacing: contract.layout.gridSpacing) {
				ForEach(Array((screen.grid ?? []).enumerated()), id: \.offset) { row in
					GridRow {
						ForEach(row.element) { cell in
							VStack(spacing: contract.layout.gridCellSpacing) {
								Image(systemName: cell.symbol ?? "circle.fill")
									.font(.system(size: 20))
									.foregroundStyle(.blue)
								Text(cell.title ?? "")
									.font(.system(size: 12))
							}
							.frame(maxWidth: .infinity)
						}
					}
				}
			}
		case "stacks":
			VStack(alignment: .leading, spacing: contract.layout.sectionSpacing) {
				Text("HStack with Spacer")
					.font(.system(size: 15, weight: .semibold))
				HStack(spacing: contract.layout.horizontalSpacing) {
					Text(screen.leading ?? "").font(.system(size: 16))
					Spacer()
					Text(screen.trailing ?? "").font(.system(size: 16, weight: .semibold))
				}
				Divider()
				Text("Nested VStack")
					.font(.system(size: 15, weight: .semibold))
				VStack(alignment: .leading, spacing: contract.layout.nestedSpacing) {
					Text(screen.nestedTitle ?? "").font(.system(size: 16, weight: .medium))
					Text(screen.nestedSubtitle ?? "")
						.font(.system(size: 14))
						.foregroundStyle(.secondary)
				}
				Divider()
				Text("HStack with spaced metrics")
					.font(.system(size: 15, weight: .semibold))
				HStack(alignment: .top, spacing: contract.layout.stackRowSpacing) {
					ForEach(screen.quickConditions ?? []) { condition in
						VStack(alignment: .leading, spacing: contract.layout.nestedSpacing) {
							Text(condition.title).font(.system(size: 12)).foregroundStyle(.secondary)
							Text(condition.value).font(.system(size: 14, weight: .medium))
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
				}
				Divider()
				Text("ZStack overlay")
					.font(.system(size: 15, weight: .semibold))
				ZStack {
					Image(systemName: "circle.fill")
						.font(.system(size: 48))
						.foregroundStyle(.blue)
					Image(systemName: screen.overlaySymbol ?? "sun.max.fill")
						.font(.system(size: 22))
						.foregroundStyle(.white)
				}
				.frame(width: contract.layout.overlaySize, height: contract.layout.overlaySize)
			}
		case "tabs":
			EmptyView()
		case "controls":
			VStack(alignment: .leading, spacing: contract.layout.controlSpacing) {
				if let field = screen.field {
					TextField(field.placeholder, text: .constant(field.value))
						.textFieldStyle(.roundedBorder)
						.accessibilityLabel(field.label)
				}
				if let toggle = screen.toggle {
					Toggle(toggle.label, isOn: .constant(toggle.value))
				}
				if let slider = screen.slider {
					VStack(alignment: .leading, spacing: contract.layout.sliderRowSpacing) {
						HStack(spacing: contract.layout.horizontalSpacing) {
							Text(slider.label).font(.system(size: 15))
							Spacer()
							Text("\(Int(slider.value))%")
								.font(.system(size: 14))
								.foregroundStyle(.secondary)
						}
						Slider(value: .constant(slider.value), in: slider.min...slider.max)
					}
				}
				if let progress = screen.progress {
					VStack(alignment: .leading, spacing: contract.layout.progressSpacing) {
						Text(progress.label).font(.system(size: 15))
						ProgressView(value: progress.value)
					}
				}
			}
		default:
			Text("Unknown comparison fixture")
		}
	}

	private func buttonView(_ button: Sample) -> AnyView {
		let label: AnyView
		if let symbol = button.symbol {
			label = AnyView(Label(button.title ?? "", systemImage: symbol))
		} else {
			label = AnyView(Text(button.title ?? ""))
		}
		let role: ButtonRole? = button.role.flatMap { value in
			switch value {
			case "destructive": return .destructive
			case "cancel": return .cancel
			default: return nil
			}
		}
		let base = Button(role: role) {} label: { label }
		let styled: AnyView
		switch button.style ?? "default" {
		case "bordered": styled = AnyView(base.buttonStyle(.bordered))
		case "borderedProminent": styled = AnyView(base.buttonStyle(.borderedProminent))
		case "plain": styled = AnyView(base.buttonStyle(.plain))
		default: styled = AnyView(base.buttonStyle(.automatic))
		}
		let sized = button.size.map { AnyView(styled.font(.system(size: $0))) } ?? styled
		let accessible = sized.disabled(button.disabled ?? false)
		if let accessibilityLabel = button.accessibilityLabel {
			return AnyView(accessible.accessibilityLabel(accessibilityLabel))
		}
		return AnyView(accessible)
	}

	private var tabsContent: some View {
		TabView(selection: $selectedTab) {
			ForEach(Array((screen.tabs ?? []).enumerated()), id: \.element.id) { item in
				let tab = item.element
				ScrollView {
					VStack(alignment: .leading, spacing: contract.layout.sectionSpacing) {
						Text(tab.heading).font(.system(size: 24, weight: .bold))
						Text(tab.subtitle).font(.system(size: 16))
						Text(tab.detail).font(.system(size: 14)).foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(contract.layout.horizontalInset)
				}
				.tabItem { Label(tab.title, systemImage: tab.symbol) }
				.tag(item.offset)
			}
		}
	}

	var body: some View {
		Group {
			if screen.id == "tabs" {
				tabsContent
			} else {
				ScrollView {
					VStack(alignment: .leading, spacing: contract.layout.stackSpacing) {
						Text(screen.title)
							.font(.system(size: 28, weight: .bold))
						Text("Same fixture contract · \(contract.environment.device) · \(contract.environment.runtime)")
							.font(.system(size: 13))
							.foregroundStyle(.secondary)
						Divider()
						fixtureContent
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(contract.layout.horizontalInset)
				}
			}
		}
		.background(Color(uiColor: .systemBackground))
		.preferredColorScheme(.light)
		.statusBarHidden(false)
		.environment(\.locale, Locale(identifier: contract.environment.locale))
		.environment(\.layoutDirection, .leftToRight)
		.environment(\.dynamicTypeSize, .large)
	}
}

@main
private struct ComparisonHost: App {
	private let contract: Contract
	private let screen: Screen

	init() {
		do {
			let loaded = try loadContract()
			contract = loaded
			screen = try selectedScreen(in: loaded)
		} catch {
			fatalError("Could not load SwiftUI comparison contract: \(error)")
		}
	}

	var body: some Scene {
		WindowGroup {
			ComparisonView(contract: contract, screen: screen)
		}
	}
}
