import AppKit
import Virtualization
import VMStorage

@MainActor
// VZVirtualMachine uses the main queue by default, including delegate callbacks.
final class VirtualMachine: NSObject, ObservableObject, @preconcurrency VZVirtualMachineDelegate {
    @Published var machine: VZVirtualMachine?
    @Published var status = "Ready"
    @Published var error: String?
    @Published var busy = false
    weak var guestView: RetinaGuestView?
    private var storage: VMStorage?

    var active: Bool { machine != nil }
    var directory: URL {
        if let override = ProcessInfo.processInfo.environment["OHMANSY_VM_DIRECTORY"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ohmansy/VM", isDirectory: true)
    }

    func start(installer: URL?, cpus: Int, memoryGiB: Int) {
        guard !active, !busy else { return }
        busy = true
        error = nil
        status = "Starting…"
        do {
            guard VZVirtualMachine.isSupported else {
                throw LaunchError.unsupported
            }
            let storage = try VMStorage(directory: directory)
            try storage.prepareDisk()
            let config = VZVirtualMachineConfiguration()
            config.cpuCount = cpus
            config.memorySize = UInt64(memoryGiB) * 1024 * 1024 * 1024
            config.platform = VZGenericPlatformConfiguration()
            let boot = VZEFIBootLoader()
            if FileManager.default.fileExists(atPath: storage.efi.path) {
                boot.variableStore = VZEFIVariableStore(url: storage.efi)
            } else {
                boot.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: storage.efi)
            }
            config.bootLoader = boot
            let disk = try VZDiskImageStorageDeviceAttachment(url: storage.disk, readOnly: false)
            config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
            if let installer {
                let iso = try VZDiskImageStorageDeviceAttachment(url: installer, readOnly: true)
                config.storageDevices.insert(VZUSBMassStorageDeviceConfiguration(attachment: iso), at: 0)
            }
            let graphics = VZVirtioGraphicsDeviceConfiguration()
            // Use a Retina-sized initial mode while the view is being attached.
            // The view then requests the exact size of its drawable area.
            let scale = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
            graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: Int(1100 * scale), heightInPixels: Int(650 * scale))]
            config.graphicsDevices = [graphics]
            config.keyboards = [VZUSBKeyboardConfiguration()]
            config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
            let clipboard = VZSpiceAgentPortAttachment()
            clipboard.sharesClipboard = true
            let clipboardPort = VZVirtioConsolePortConfiguration()
            clipboardPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
            clipboardPort.attachment = clipboard
            let console = VZVirtioConsoleDeviceConfiguration()
            console.ports[0] = clipboardPort
            config.consoleDevices = [console]
            if let resources = Bundle.main.resourceURL?.appendingPathComponent("Guest"),
               FileManager.default.fileExists(atPath: resources.path) {
                let integration = VZVirtioFileSystemDeviceConfiguration(tag: "ohmansy")
                integration.share = VZSingleDirectoryShare(directory:
                    VZSharedDirectory(url: resources, readOnly: true))
                config.directorySharingDevices = [integration]
            }
            config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
            config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
            let network = VZVirtioNetworkDeviceConfiguration()
            network.attachment = VZNATNetworkDeviceAttachment()
            if FileManager.default.fileExists(atPath: storage.macAddress.path) {
                let value = try String(contentsOf: storage.macAddress, encoding: .utf8)
                guard let address = VZMACAddress(string: value) else { throw LaunchError.invalidMAC }
                network.macAddress = address
            } else {
                network.macAddress = .randomLocallyAdministered()
                try network.macAddress.string.write(to: storage.macAddress, atomically: true, encoding: .utf8)
            }
            config.networkDevices = [network]
            let sound = VZVirtioSoundDeviceConfiguration()
            let output = VZVirtioSoundDeviceOutputStreamConfiguration()
            output.sink = VZHostAudioOutputStreamSink()
            sound.streams = [output]
            config.audioDevices = [sound]
            try config.validate()
            let machine = VZVirtualMachine(configuration: config)
            machine.delegate = self
            self.storage = storage
            self.machine = machine
            machine.start { [weak self] result in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success: self.status = "Running"
                case .failure(let error): self.finish(error: error)
                }
            }
        } catch {
            finish(error: error)
        }
    }

    func shutDown() {
        guard let machine, machine.canRequestStop else { return }
        do {
            try machine.requestStop()
            status = "Waiting for NixOS to shut down…"
        } catch { self.error = error.localizedDescription }
    }

    func forceStop() {
        guard let machine, machine.canStop, !busy else { return }
        busy = true
        machine.stop { [weak self] error in
            guard let self else { return }
            if let error {
                self.busy = false
                self.error = error.localizedDescription
            } else { self.finish() }
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) { finish() }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        finish(error: error)
    }

    private func finish(error: Error? = nil) {
        machine = nil
        storage = nil
        busy = false
        status = error == nil ? "Stopped" : "Could not run the VM"
        self.error = error?.localizedDescription
    }
}

enum LaunchError: LocalizedError {
    case unsupported, invalidMAC
    var errorDescription: String? {
        switch self {
        case .unsupported: "Virtualization is unavailable on this Mac."
        case .invalidMAC: "The saved VM network address is invalid."
        }
    }
}
