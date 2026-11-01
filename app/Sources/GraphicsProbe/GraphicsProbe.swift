import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct GraphicsProbeApp: App {
    @StateObject private var probe = Probe()

    var body: some Scene {
        Window("ohmansy GPU test", id: "probe") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Accelerated NixOS graphics").font(.title2.bold())
                Text("Test QEMU and VirGL with a diskless ARM NixOS live session, or an independent copy of your installed VM.")
                Button("Choose ISO…") { probe.chooseISO() }.disabled(probe.running)
                Text(probe.iso?.lastPathComponent ?? "Choose a graphical aarch64 NixOS ISO.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Start live GPU test") { probe.start() }
                        .disabled(probe.iso == nil || probe.running)
                    Button("Start accelerated copy") { probe.start(copy: true) }
                        .disabled(probe.running)
                }
                Text("The accelerated copy imports your installed VM once, after it shuts down. Later changes in either VM stay separate.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Show logs") {
                        NSWorkspace.shared.open(probe.logDirectory ?? probe.directory)
                    }
                    Button("Inspect live guest GPU") { probe.diagnose() }
                        .disabled(probe.diagnosing)
                    Button("Shut down live test") { probe.diagnose(action: "shutdown") }
                        .disabled(probe.diagnosing)
                }
                Text(probe.status).font(.callout).textSelection(.enabled)
                Button("Read copy boot log") { probe.diagnose(action: "console", copy: true) }
                    .disabled(probe.diagnosing)
                Text("Requires the locally installed Try Omarchy runtime and Homebrew Python 3. The test desktop opens in a separate QEMU window; close it after testing.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 560)
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class Probe: ObservableObject {
    @Published var iso: URL?
    @Published var running = false
    @Published var status = "Ready"
    @Published var diagnosing = false
    @Published var logDirectory: URL?
    private var process: Process?
    private var output: FileHandle?
    // This development harness is built under the checkout's dist/ directory.
    let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".local/gpu-probe")

    func chooseISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { iso = panel.url }
    }

    func diagnose(action: String = "diagnose", copy: Bool = false) {
        guard !diagnosing else { return }
        do {
            let state = copy ? directory.deletingLastPathComponent().appendingPathComponent("gpu-vm") : directory
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
            child.arguments = [Bundle.main.url(forResource: "gpu-probe", withExtension: "py")!.path,
                               action, "--state", state.path]
            child.terminationHandler = { [weak self] child in
                let result = child.terminationStatus
                Task { @MainActor in
                    self?.diagnosing = false
                    self?.status = result == 0 ?
                        (action == "console" ? "Boot console and runtime status saved." :
                            (action == "shutdown" ? "Requested a clean shutdown of the live test." : "Guest GPU report saved in guest-gpu.log.")) :
                        "Guest diagnostics could not finish. See guest-gpu.log."
                }
            }
            try child.run()
            logDirectory = state
            diagnosing = true
            status = action == "shutdown" ? "Requesting shutdown…" : "Reading the guest's serial console…"
        } catch { status = error.localizedDescription }
    }

    func start(copy: Bool = false) {
        guard !running, copy || iso != nil else { return }
        do {
            let state = copy ? directory.deletingLastPathComponent().appendingPathComponent("gpu-vm") : directory
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            logDirectory = state
            let log = state.appendingPathComponent("launcher.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            output = try FileHandle(forWritingTo: log)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
            var arguments = [Bundle.main.url(forResource: "gpu-probe", withExtension: "py")!.path,
                             copy ? "start-copy" : "start", "--state", state.path]
            if !copy, let iso { arguments += ["--iso", iso.path] }
            child.arguments = arguments
            child.standardOutput = output
            child.standardError = output
            child.terminationHandler = { [weak self] child in
                let exitCode = child.terminationStatus
                Task { @MainActor in
                    guard let self else { return }
                    try? self.output?.close()
                    self.output = nil
                    self.process = nil
                    self.running = false
                    self.status = exitCode == 0 ? "GPU test stopped." :
                        ((try? String(contentsOf: log, encoding: .utf8)) ?? "GPU test failed; see logs.")
                }
            }
            try child.run()
            process = child
            running = true
            status = "GPU test starting. QEMU owns the test desktop window."
        } catch {
            try? output?.close()
            output = nil
            status = error.localizedDescription
        }
    }
}
