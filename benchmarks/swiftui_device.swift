import UIKit
import SwiftUI
import QuartzCore
import Darwin.Mach

private let scrollSpeed: CGFloat = 1500
private let duration: CFTimeInterval = 4
private let traceDuration: CFTimeInterval = 30

private func findScroll(_ view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView,
       scroll.contentSize.height > scroll.bounds.height { return scroll }
    for child in view.subviews {
        if let scroll = findScroll(child) { return scroll }
    }
    return nil
}

private func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

private final class ScrollProbe: NSObject {
    weak var window: UIWindow?
    weak var scroll: UIScrollView?
    var link: CADisplayLink?
    let kind: String
    let count: Int
    let started: CFTimeInterval
    var firstFrame: CFTimeInterval = 0
    var previous: CFTimeInterval = 0
    var frames = 0
    var hitches = 0
    var longest: CFTimeInterval = 0
    var peak: UInt64
    var reported = false

    init(window: UIWindow, kind: String, count: Int, started: CFTimeInterval, peak: UInt64) {
        self.window = window
        self.kind = kind
        self.count = count
        self.started = started
        self.peak = peak
    }

    func begin() {
        let display = CADisplayLink(target: self, selector: #selector(tick(_:)))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        display.add(to: .main, forMode: .common)
        link = display
    }

    @objc private func tick(_ display: CADisplayLink) {
        let now = CACurrentMediaTime()
        if scroll == nil, let window { scroll = findScroll(window) }
        guard let scroll, let window else { return }
        if firstFrame == 0 { firstFrame = now }
        let elapsed = now - firstFrame
        let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
        if maximum > 0 {
            let cycle = (CGFloat(elapsed) * scrollSpeed).truncatingRemainder(dividingBy: maximum * 2)
            let offset = cycle <= maximum ? cycle : maximum * 2 - cycle
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
        let target = Double(window.windowScene?.screen.maximumFramesPerSecond ?? 120)
        if previous != 0 {
            let gap = now - previous
            longest = max(longest, gap)
            if gap > 2 / target { hitches += 1 }
        }
        previous = now
        frames += 1
        peak = max(peak, footprint())
        if !reported && elapsed >= duration {
            reported = true
            NSLog("BENCH_RESULT engine=SwiftUI kind=%@ rows=%d firstFrameMs=%.1f fps=%.1f hitches=%d longestFrameMs=%.1f peakFootprintMiB=%.1f displayHz=%.0f",
                  kind, count, (firstFrame - started) * 1000, Double(frames) / elapsed,
                  hitches, longest * 1000, Double(peak) / (1024 * 1024), target)
        }
        if elapsed >= traceDuration {
            display.invalidate()
            link = nil
        }
    }
}

@objc(BenchmarkSceneDelegate)
final class BenchmarkSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var probe: ScrollProbe?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let started = CACurrentMediaTime()
        let initialFootprint = footprint()
        let environment = ProcessInfo.processInfo.environment
        let kind = environment["SWIFTUI_BENCH_KIND"] ?? "list"
        let count = Int(environment["SWIFTUI_BENCH_ROWS"] ?? "1000") ?? 1000
        let rows = Array(1...count)
        let content: AnyView
        switch kind {
        case "eager":
            content = AnyView(ScrollView {
                VStack { ForEach(rows, id: \.self) { index in Text("Item \(index)") } }
            })
        case "lazy":
            content = AnyView(ScrollView {
                LazyVStack { ForEach(rows, id: \.self) { index in Text("Item \(index)") } }
            })
        default:
            content = AnyView(List(rows, id: \.self) { index in Text("Item \(index)") })
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        self.window = window
        let probe = ScrollProbe(window: window, kind: kind, count: count,
                                started: started, peak: initialFootprint)
        self.probe = probe
        probe.begin()
    }
}

@main
final class BenchmarkAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        configuration.delegateClass = BenchmarkSceneDelegate.self
        return configuration
    }
}
