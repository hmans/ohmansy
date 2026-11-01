import AppKit

/// The runtime owns the app's only window, including its launch screen.
@main
@MainActor
final class RuntimeApp: NSObject, NSApplicationDelegate {
    private var process: Process?
    private var logHandle: FileHandle?

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
            .appendingPathComponent(".local/gpu-vm")
        let directory: URL
        if let saved = defaults.string(forKey: "acceleratedVMDirectory") {
            directory = URL(fileURLWithPath: saved, isDirectory: true)
        } else if FileManager.default.fileExists(atPath: developmentCopy.appendingPathComponent("disk.raw").path) {
            directory = developmentCopy
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Ohmansy/AcceleratedVM")
        }
        defaults.set(directory.path, forKey: "acceleratedVMDirectory")
        let log = directory.appendingPathComponent("app-launcher.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: log)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
            task.arguments = [Bundle.main.resourceURL!.appendingPathComponent("GPURuntime/gpu-probe.py").path,
                "start-copy", "--state", directory.path, "--helper",
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
                        alert.messageText = "Could not start NixOS"
                        alert.informativeText = String(((try? String(contentsOf: log, encoding: .utf8)) ?? "See app-launcher.log.").suffix(2000))
                        alert.runModal()
                    }
                    NSApp.terminate(nil)
                }
            }
            try task.run()
            process = task
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not start try ohmansy"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = activateRuntime()
        return false
    }
}
