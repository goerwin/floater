import AppKit
import ApplicationServices

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private struct SmokeTest {
    static func main() {
        setbuf(stdout, nil)
        do {
            guard AXIsProcessTrusted() else {
                throw SmokeFailure(description: "Enable Accessibility for the terminal or app running Scripts/test-app.sh, then retry.")
            }
            if CommandLine.arguments.dropFirst().first == "--check-access" { return }
            guard CommandLine.arguments.count == 3 else {
                throw SmokeFailure(description: "Run Scripts/test-app.sh.")
            }
            try AppSmokeTest(
                bundle: URL(fileURLWithPath: CommandLine.arguments[1]),
                directory: URL(fileURLWithPath: CommandLine.arguments[2])
            ).run()
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}

@MainActor
private final class AppSmokeTest {
    let bundle: URL
    let directory: URL
    var application: NSRunningApplication?
    var root: AXUIElement { AXUIElementCreateApplication(application!.processIdentifier) }

    init(bundle: URL, directory: URL) {
        self.bundle = bundle
        self.directory = directory
    }

    func run() throws {
        let info = try require(Bundle(url: bundle)?.infoDictionary, "Missing app bundle")
        try check(info["LSUIElement"] as? Bool == true, "App must run in the menu bar")
        let executable = bundle.appendingPathComponent("Contents/MacOS/floater-cli").path
        try check(FileManager.default.isExecutableFile(atPath: executable), "Bundled CLI is missing")
        defer { application?.terminate() }

        try launch()
        try wait("normal app-icon launch") { self.element("prompt") != nil }
        try wait("disabled Run after launch") {
            self.element("run").map { self.attribute($0, kAXEnabledAttribute) as? Bool == false } == true
        }
        print("PASS: app bundle launches through macOS without development flags")

        try menu("History")
        try wait("History menu action") { self.element("historySearch") != nil }
        try menu("Open")
        try check(element("historySearch") != nil, "Open must keep the current History view")
        try menu("New")
        try wait("New menu action") { self.element("prompt") != nil }
        try set(try require(element("prompt"), "Prompt missing"), value: "Smoke draft")
        try press(try require(element("dismiss"), "Dismiss missing"))
        try wait("dismiss") { self.windows.isEmpty }
        try menu("Open")
        try wait("Open menu action") { self.element("prompt") != nil }
        try check(string(try require(element("prompt"), "Prompt missing"), kAXValueAttribute) == "Smoke draft", "Open must restore the draft")
        print("PASS: real menu dispatch for Open, New, and History")

        try process("/usr/bin/open", [bundle.path])
        try wait("app-icon reopen") { self.element("prompt").map { self.string($0, kAXValueAttribute).isEmpty } == true }
        print("PASS: macOS reopen event starts New")
        try checkDragBehavior()

        let title = "CLI smoke \(UUID().uuidString)"
        try process(executable, ["--prompt", "Reply with OK.", "--input", "Smoke input", "--title", title])
        try wait("bundled CLI URL delivery") { self.windows.contains { self.string($0, kAXTitleAttribute) == title } }
        try wait("Foundation Models response", timeout: 45) {
            let generating = self.descendants(self.root).contains { self.string($0, kAXDescriptionAttribute) == "Generating response" }
            return !generating && (self.element("responseText") != nil || self.texts.contains { $0.contains("Apple Intelligence") && !$0.contains("Thinking") })
        }
        if let response = element("responseText") {
            let text = try require(descendants(response).first {
                string($0, kAXRoleAttribute) == kAXStaticTextRole && !string($0, kAXValueAttribute).isEmpty
            }, "Generated response text missing")
            try check(string(text, kAXValueAttribute) != "No response was returned.", "Model returned an empty response")
            let window = try require(windows.first, "Response window missing")
            let frame = try bounds(window)
            let textFrame = try bounds(text)
            try drag(from: CGPoint(x: textFrame.minX + 2, y: textFrame.midY), by: CGVector(dx: 20, dy: 0))
            try check(try bounds(window).origin == frame.origin, "Selecting response text must not move the window")
            let summary = try require(descendants(window).first { string($0, kAXHelpAttribute).contains("Show full prompt") }, "Prompt summary button missing")
            try checkStationaryDrag(summary, label: "prompt summary")
            print("PASS: bundled CLI delivers a request to Foundation Models")
        } else {
            print("SKIP: model generation unavailable on this Mac; CLI delivery and availability message verified")
        }

        try menu("Quit Floater \(info["CFBundleShortVersionString"] as? String ?? "")")
        try wait("Quit menu action") { self.application?.isTerminated == true }
        let coldTitle = "URL smoke \(UUID().uuidString)"
        var components = URLComponents()
        components.scheme = "floater"
        components.host = "prompt"
        components.queryItems = [URLQueryItem(name: "prompt", value: "Reply with OK."), URLQueryItem(name: "title", value: coldTitle)]
        try launch(url: try require(components.url, "Cannot encode smoke URL"))
        try wait("cold URL launch") { self.windows.contains { self.string($0, kAXTitleAttribute) == coldTitle } }
        try check(element("prompt") == nil, "Cold URL launch must not replace the request with New")
        print("PASS: cold URL launch and Quit menu action")
        print("Smoke tests passed.")
    }

    func launch(url: URL? = nil) throws {
        var arguments = ["--env", "FLOATER_HISTORY_PATH=\(directory.appendingPathComponent("history.json").path)"]
        if let url {
            arguments += ["-a", bundle.path, url.absoluteString]
        } else {
            arguments += ["-n", bundle.path]
        }
        try process("/usr/bin/open", arguments)
        try wait("Floater process") {
            self.application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.goerwin.Floater")
                .first { !$0.isTerminated && $0.bundleURL?.standardizedFileURL == self.bundle.standardizedFileURL }
            return self.application != nil
        }
    }

    var windows: [AXUIElement] { attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    var texts: [String] { descendants(root).map { string($0, kAXValueAttribute) }.filter { !$0.isEmpty } }

    func element(_ identifier: String) -> AXUIElement? {
        descendants(root).first { string($0, kAXIdentifierAttribute) == identifier }
    }

    func menu(_ title: String) throws {
        let extras = try require(attribute(root, kAXExtrasMenuBarAttribute), "Floater status menu missing") as! AXUIElement
        let item = try require(descendants(extras).first { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }, "Floater status item missing")
        AXUIElementSetMessagingTimeout(item, 1)
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        try check(result == .success || result == .cannotComplete, "Cannot open Floater's status menu: \(result.rawValue)")
        var action: AXUIElement?
        try wait("menu item \(title)") {
            action = self.descendants(item).first { self.string($0, kAXTitleAttribute) == title }
            return action != nil
        }
        try press(action!)
    }

    func checkDragBehavior() throws {
        var window = try require(windows.first, "Window missing")
        var frame = try bounds(window)
        try drag(from: CGPoint(x: frame.minX + 8, y: frame.midY), by: CGVector(dx: 60, dy: 35))
        try wait("panel background drag") { try self.bounds(window).origin != frame.origin }
        frame = try bounds(window)
        try drag(from: CGPoint(x: frame.minX + 120, y: frame.minY + 20), by: CGVector(dx: -30, dy: -15))
        try wait("header drag") { try self.bounds(window).origin != frame.origin }
        let label = try require(descendants(root).first { string($0, kAXValueAttribute) == "Prompt" }, "Prompt label missing")
        let labelFrame = try bounds(label)
        frame = try bounds(window)
        try drag(from: CGPoint(x: labelFrame.midX, y: labelFrame.midY), by: CGVector(dx: 30, dy: 15))
        try wait("noninteractive label drag") { try self.bounds(window).origin != frame.origin }
        let updatedLabelFrame = try bounds(label)
        frame = try bounds(window)
        try drag(from: CGPoint(x: frame.minX + 150, y: updatedLabelFrame.maxY + 4), by: CGVector(dx: -30, dy: -15))
        try wait("editor spacing drag") { try self.bounds(window).origin != frame.origin }
        print("PASS: body background drags the panel")

        let prompt = try require(element("prompt"), "Prompt missing")
        try set(prompt, value: "Drag to select this text")
        for identifier in ["prompt", "new", "run"] {
            try checkStationaryDrag(try require(element(identifier), "\(identifier) missing"), label: identifier)
        }
        try menu("History")
        try wait("History window") { self.element("historySearch") != nil }
        window = try require(windows.first, "History window missing")
        frame = try bounds(window)
        try drag(from: CGPoint(x: frame.minX + 8, y: frame.midY), by: CGVector(dx: -60, dy: -35))
        try wait("History background drag") { try self.bounds(window).origin != frame.origin }
        for identifier in ["historySearch", "historyList"] {
            try checkStationaryDrag(try require(element(identifier), "\(identifier) missing"), label: identifier)
        }
        try menu("New")
        try wait("empty composer") { self.element("prompt") != nil }
        let disabledRun = try require(element("run"), "Run missing")
        try check(attribute(disabledRun, kAXEnabledAttribute) as? Bool == false, "Run must be disabled for an empty prompt")
        try checkStationaryDrag(disabledRun, label: "disabled Run")
        print("PASS: History background drags; text editors and buttons keep mouse handling")
    }

    func checkStationaryDrag(_ control: AXUIElement, label: String) throws {
        let window = try require(windows.first, "Window missing")
        let frame = try bounds(window)
        let controlFrame = try bounds(control)
        try drag(from: CGPoint(x: controlFrame.midX, y: controlFrame.midY), by: CGVector(dx: 90, dy: 40))
        try check(try bounds(window).origin == frame.origin, "Dragging \(label) must not move the window")
    }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    func descendants(_ element: AXUIElement) -> [AXUIElement] {
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return [element] + children.flatMap(descendants)
    }

    func bounds(_ element: AXUIElement) throws -> CGRect {
        let position = try require(attribute(element, kAXPositionAttribute), "Element position missing") as! AXValue
        let size = try require(attribute(element, kAXSizeAttribute), "Element size missing") as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        try check(AXValueGetValue(position, .cgPoint, &point) && AXValueGetValue(size, .cgSize, &dimensions), "Cannot read element bounds")
        return CGRect(origin: point, size: dimensions)
    }

    func press(_ element: AXUIElement) throws {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        try check(result == .success, "Cannot press \(string(element, kAXRoleAttribute)) \(string(element, kAXTitleAttribute)): \(result.rawValue); actions: \(actions as? [String] ?? [])")
    }

    func set(_ element: AXUIElement, value: String) throws {
        try check(AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success, "Cannot edit text")
    }

    func drag(from start: CGPoint, by offset: CGVector) throws {
        for step in 0...12 {
            let point = CGPoint(x: start.x + offset.dx * CGFloat(step) / 12, y: start.y + offset.dy * CGFloat(step) / 12)
            let type: CGEventType = step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
            let event = try require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left), "Cannot create drag event")
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    func wait(_ message: String, timeout: TimeInterval = 8, until predicate: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try predicate() { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        let titles = application == nil ? [] : windows.map { string($0, kAXTitleAttribute) }
        let identifiers = application == nil ? [] : windows.flatMap(descendants).map { string($0, kAXIdentifierAttribute) }.filter { !$0.isEmpty }
        throw SmokeFailure(description: "Timed out waiting for \(message); Floater windows: \(titles); controls: \(identifiers)")
    }

    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw SmokeFailure(description: message) }
    }

    func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SmokeFailure(description: message) }
        return value
    }

    func process(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "\(URL(fileURLWithPath: executable).lastPathComponent) exited with \(process.terminationStatus)")
    }
}
