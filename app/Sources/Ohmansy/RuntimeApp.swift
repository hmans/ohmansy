import AppKit

/// The runtime owns the app's only window, including its launch screen.
@main
@MainActor
final class RuntimeApp: NSObject, NSApplicationDelegate {
    private var process: Process?
    private var logHandle: FileHandle?
    private var preparationWindow: NSWindow?
    private var preparationTimer: Timer?

    static func main() {
        if CommandLine.arguments.contains("--original-vm") {
            OhmansyApp.main()
            return
        }
        let app = NSApplication.shared
        let delegate = RuntimeApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    private func activateRuntime() -> Bool {
        guard let runtime = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "dev.hmans.ohmansy.runtime"
        }) else { return false }
        runtime.activate()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateRuntime() { NSApp.terminate(nil); return }
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["cpus": 4, "memoryGiB": 4])
        let developmentCopy = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/factory-preview")
        let directory: URL
        if let saved = defaults.string(forKey: "factoryVMDirectory") {
            directory = URL(fileURLWithPath: saved, isDirectory: true)
        } else if FileManager.default.fileExists(atPath: developmentCopy.appendingPathComponent("factory.json").path) {
            directory = developmentCopy
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Ohmansy/FactoryVM")
        }
        defaults.set(directory.path, forKey: "factoryVMDirectory")
        let log = directory.appendingPathComponent("app-launcher.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: log)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
            task.arguments = [Bundle.main.resourceURL!.appendingPathComponent("GPURuntime/factory-vm.py").path,
                "--factory", Bundle.main.resourceURL!.appendingPathComponent("Factory").path,
                "--state", directory.path, "--helper",
                Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/try ohmansy.app").path,
                "--cpus", String(max(1, defaults.integer(forKey: "cpus"))),
                "--memory-mib", String(max(4, defaults.integer(forKey: "memoryGiB")) * 1024)]
            task.standardOutput = logHandle
            task.standardError = logHandle
            task.terminationHandler = { task in
                let code = task.terminationStatus
                Task { @MainActor in
                    if code != 0 {
                        let alert = NSAlert()
                        alert.messageText = "Could not start ohmansy"
                        alert.informativeText = String(((try? String(contentsOf: log, encoding: .utf8)) ?? "See app-launcher.log.").suffix(2000))
                        alert.runModal()
                    }
                    NSApp.terminate(nil)
                }
            }
            try task.run()
            process = task
            showPreparationWindow()
            preparationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if NSWorkspace.shared.runningApplications.contains(where: {
                        $0.bundleIdentifier == "dev.hmans.ohmansy.runtime"
                    }) {
                        self.preparationWindow?.close()
                        self.preparationWindow = nil
                        self.preparationTimer?.invalidate()
                        self.preparationTimer = nil
                        _ = self.activateRuntime()
                    }
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not start try ohmansy"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func showPreparationWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "try ohmansy"
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Preparing ohmansy…")
        label.frame = NSRect(x: 28, y: 65, width: 304, height: 24)
        label.font = .systemFont(ofSize: 17, weight: .medium)
        let progress = NSProgressIndicator(frame: NSRect(x: 28, y: 30, width: 304, height: 16))
        progress.isIndeterminate = true
        progress.style = .bar
        progress.startAnimation(nil)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(progress)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        preparationWindow = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = activateRuntime()
        return false
    }
}
