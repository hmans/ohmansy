import SwiftUI
import Virtualization
import UniformTypeIdentifiers
import VMDisplay

struct OhmansyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var vm = VirtualMachine()

    var body: some Scene {
        Window("try ohmansy", id: "main") {
            ContentView(vm: vm)
                .onAppear { delegate.vm = vm }
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1100, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var vm: VirtualMachine?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard vm?.active == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Shut down NixOS before quitting"
        alert.informativeText = "The VM is still running. Shut it down, then quit try ohmansy."
        alert.addButton(withTitle: "Shut Down NixOS")
        alert.addButton(withTitle: "Keep Running")
        if alert.runModal() == .alertFirstButtonReturn {
            vm?.shutDown()
        }
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct ContentView: View {
    @ObservedObject var vm: VirtualMachine
    @State private var installer: URL?
    @State private var confirmStop = false
    @AppStorage("cpus") private var cpus = 4
    @AppStorage("memoryGiB") private var memoryGiB = 4
    @AppStorage("retinaDisplay") private var retinaDisplay = true

    var body: some View {
        VStack(spacing: 0) {
            if let machine = vm.machine {
                GeometryReader { geometry in
                    let size = DisplayGeometry.alignedViewSize(geometry.size)
                    GuestDisplay(machine: machine, retina: retinaDisplay,
                                 viewChanged: { vm.guestView = $0 })
                        .frame(width: size.width, height: size.height)
                }
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.black.opacity(0.3), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
                .padding(10)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    Text("NixOS. On your Mac.").font(.largeTitle.bold())
                    Text("Start with a 64-bit ARM NixOS ISO. Install to the virtual disk, then start without the ISO. Your disk stays between runs.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Choose Installer ISO…", action: chooseInstaller)
                        Text(installer?.lastPathComponent ?? "No installer attached")
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        if installer != nil { Button("Eject") { installer = nil } }
                    }
                    Link("Download NixOS (choose 64-bit ARM)", destination: URL(string: "https://nixos.org/download/")!)
                    Stepper("CPU cores: \(cpus)", value: $cpus, in: 1...max(1, ProcessInfo.processInfo.processorCount))
                    Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB,
                            in: 2...max(2, Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) - 2))
                    Text("64 GiB virtual disk · NAT networking · EFI boot")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(installer == nil ? "Start NixOS" : "Start with Installer") {
                            vm.start(installer: installer, cpus: cpus, memoryGiB: memoryGiB)
                        }.buttonStyle(.borderedProminent).disabled(vm.busy)
                        Button("Show VM Files") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.directory.path) }
                    }
                    Text("First prototype: software-rendered display. ohmansy desktop configuration and Mac integrations are still to come.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(40).frame(maxWidth: 650, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowChrome())
        .navigationSubtitle(vm.status)
        .toolbar {
            if vm.active {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        vm.guestView?.focusKeyboard()
                    } label: {
                        Label("Focus Keyboard", systemImage: "keyboard")
                    }
                    .help("Send keyboard input to NixOS")

                    Menu {
                        Picker("Display", selection: $retinaDisplay) {
                            Text("Retina").tag(true)
                            Text("Larger UI").tag(false)
                        }
                    } label: {
                        Label("Display", systemImage: "display")
                    }
                    .help(retinaDisplay ? "Display: Retina" : "Display: Larger UI")

                    Menu {
                        Button(action: vm.shutDown) {
                            Label("Shut Down", systemImage: "power")
                        }
                        Divider()
                        Button(role: .destructive) { confirmStop = true } label: {
                            Label("Force Stop…", systemImage: "stop.circle")
                        }
                    } label: {
                        Label("Power", systemImage: "power")
                    }
                    .help("Power options")
                    .disabled(vm.busy)
                }
            }
        }
        .alert("try ohmansy", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
        .confirmationDialog("Force stop NixOS? Unsaved changes can be lost.", isPresented: $confirmStop) {
            Button("Force Stop", role: .destructive, action: vm.forceStop)
        }
    }

    private func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { installer = panel.url }
    }
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {
        view.scheduleAppearanceUpdate()
    }

    final class ChromeView: NSView {
        private var appearanceUpdatePending = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                // A screen transition can rebuild the native title bar without
                // causing a SwiftUI update or a layout pass in this view.
                for name in [NSWindow.didChangeScreenNotification,
                             NSWindow.didChangeBackingPropertiesNotification,
                             NSWindow.didMoveNotification,
                             NSWindow.didBecomeKeyNotification,
                             NSWindow.didExitFullScreenNotification] {
                    center.addObserver(self, selector: #selector(windowAppearanceChanged(_:)),
                                       name: name, object: window)
                }
            }
            scheduleAppearanceUpdate()
        }

        @objc private func windowAppearanceChanged(_ notification: Notification) {
            scheduleAppearanceUpdate()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            scheduleAppearanceUpdate()
        }

        override func layout() {
            super.layout()
            applyAppearance()
        }

        func scheduleAppearanceUpdate() {
            guard !appearanceUpdatePending else { return }
            appearanceUpdatePending = true
            // Let AppKit and SwiftUI finish updating the toolbar first. Coalesce
            // the screen, backing-scale and move events from the same transition.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.appearanceUpdatePending = false
                self.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let window else { return }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.toolbar?.showsBaselineSeparator == true {
                window.toolbar?.showsBaselineSeparator = false
            }
        }
    }
}

struct GuestDisplay: NSViewRepresentable {
    let machine: VZVirtualMachine
    let retina: Bool
    let viewChanged: (RetinaGuestView) -> Void

    func makeNSView(context: Context) -> RetinaGuestView {
        let view = RetinaGuestView()
        view.virtualMachine = machine
        view.capturesSystemKeys = true
        // This view owns resizing. Apple's automatic resizing must not compete
        // with our explicit choice between backing pixels and logical points.
        view.automaticallyReconfiguresDisplay = false
        viewChanged(view)
        return view
    }
    func updateNSView(_ view: RetinaGuestView, context: Context) {
        view.virtualMachine = machine
        view.retina = retina
        view.scheduleResize()
    }

    static func dismantleNSView(_ view: RetinaGuestView, coordinator: ()) {
        view.cancelResize()
        view.virtualMachine = nil
    }
}

@MainActor
final class RetinaGuestView: VZVirtualMachineView {
    var retina = true
    private var resizeTask: Task<Void, Never>?
    private var requestedSize: CGSize?
    private var pendingSize: CGSize?

    func focusKeyboard() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        focusKeyboard()
        super.mouseDown(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleResize()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        scheduleResize()
    }

    override func layout() {
        super.layout()
        scheduleResize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { focusKeyboard() }
        scheduleResize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moving between Retina and non-Retina screens can change the backing
        // scale without changing the view's size in points.
        scheduleResize()
    }

    func cancelResize() {
        resizeTask?.cancel()
        resizeTask = nil
        pendingSize = nil
    }

    func scheduleResize() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
        let rect = retina ? convertToBacking(bounds) : bounds
        let size = CGSize(width: rect.width.rounded(), height: rect.height.rounded())
        // Repeated layout passes for the same size must not postpone the work
        // indefinitely while the VM is drawing frames.
        guard pendingSize != size else { return }
        cancelResize()
        pendingSize = size
        resizeTask = Task { @MainActor [weak self] in
            // Avoid a guest mode switch for every frame of a live window resize.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            self?.pendingSize = nil
            self?.resizeTask = nil
            self?.resizeDisplay()
        }
    }

    private func resizeDisplay() {
        guard window != nil, let machine = virtualMachine,
              machine.state == .running,
              let display = machine.graphicsDevices.first?.displays.first else { return }
        let rect = retina ? convertToBacking(bounds) : bounds
        let size = CGSize(width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded()))
        guard size != requestedSize else { return }
        do {
            try display.reconfigure(sizeInPixels: size)
            requestedSize = size
            toolTip = nil
        } catch {
            // Leave the current working mode intact and allow a later retry.
            toolTip = "The guest display could not resize: \(error.localizedDescription)"
        }
    }
}
