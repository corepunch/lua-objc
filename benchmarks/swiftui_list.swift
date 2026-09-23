import AppKit
import SwiftUI

let kind = ProcessInfo.processInfo.environment["SWIFTUI_BENCH_KIND"] ?? "eager"
let count = Int(ProcessInfo.processInfo.environment["SWIFTUI_BENCH_ROWS"] ?? "1000") ?? 1000
let rows = Array(0..<count)
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let started = ProcessInfo.processInfo.systemUptime
let content: AnyView
switch kind {
case "lazy":
    content = AnyView(ScrollView {
        LazyVStack { ForEach(rows, id: \.self) { index in Text("Item \(index)") } }
    })
case "list":
    content = AnyView(List(rows, id: \.self) { index in Text("Item \(index)") })
default:
    content = AnyView(ScrollView {
        VStack { ForEach(rows, id: \.self) { index in Text("Item \(index)") } }
    })
}
let host = NSHostingView(rootView: content)
host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
host.layoutSubtreeIfNeeded()
print(String(format: "SwiftUI %@ %d: %.3fs construction/layout", kind, count,
    ProcessInfo.processInfo.systemUptime - started))
withExtendedLifetime(host) {}
