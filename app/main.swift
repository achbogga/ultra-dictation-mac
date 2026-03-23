import AppKit

final class InstallerViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "Install or uninstall Ultra Dictation.")
    private let outputView = NSTextView()
    private let installButton = NSButton(title: "Install / Update", target: nil, action: nil)
    private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
    private let readmeButton = NSButton(title: "Open README", target: nil, action: nil)
    private let bootCheckbox = NSButton(checkboxWithTitle: "Start helper automatically at login", target: nil, action: nil)
    private let hotkeyLabel = NSTextField(labelWithString: "Karabiner key_code:")
    private let hotkeyField = NSTextField(string: "")
    private let defaults = UserDefaults.standard
    private let bootPreferenceKey = "launchAtLogin"
    private let hotkeyPreferenceKey = "karabinerHotkey"
    private let defaultHotkey = "f13"
    private let validHotkeyCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        statusLabel.frame = NSRect(x: 24, y: 472, width: 672, height: 28)

        installButton.frame = NSRect(x: 24, y: 430, width: 150, height: 32)
        uninstallButton.frame = NSRect(x: 184, y: 430, width: 110, height: 32)
        readmeButton.frame = NSRect(x: 304, y: 430, width: 120, height: 32)

        installButton.target = self
        installButton.action = #selector(runInstall)
        uninstallButton.target = self
        uninstallButton.action = #selector(runUninstall)
        readmeButton.target = self
        readmeButton.action = #selector(openReadme)
        bootCheckbox.target = self
        bootCheckbox.action = #selector(updateBootPreference)
        bootCheckbox.frame = NSRect(x: 436, y: 432, width: 260, height: 24)
        bootCheckbox.state = defaults.bool(forKey: bootPreferenceKey) ? .on : .off
        hotkeyLabel.frame = NSRect(x: 24, y: 394, width: 150, height: 24)
        hotkeyField.frame = NSRect(x: 176, y: 390, width: 160, height: 28)
        hotkeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        hotkeyField.placeholderString = defaultHotkey
        hotkeyField.stringValue = defaults.string(forKey: hotkeyPreferenceKey) ?? defaultHotkey

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 24, width: 672, height: 352))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        outputView.isEditable = false
        outputView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = outputView

        view.addSubview(statusLabel)
        view.addSubview(installButton)
        view.addSubview(uninstallButton)
        view.addSubview(readmeButton)
        view.addSubview(bootCheckbox)
        view.addSubview(hotkeyLabel)
        view.addSubview(hotkeyField)
        view.addSubview(scrollView)
    }

    @objc private func runInstall() {
        let bootArg = bootCheckbox.state == .on ? "--enable-on-boot" : "--disable-on-boot"
        let hotkey = normalizedHotkey(from: hotkeyField.stringValue)
        guard isValidHotkey(hotkey) else {
            statusLabel.stringValue = "Invalid hotkey."
            append("Hotkey must use lowercase letters, numbers, and underscores only.\n")
            return
        }

        defaults.set(hotkey, forKey: hotkeyPreferenceKey)
        hotkeyField.stringValue = hotkey
        runScript(named: "install.sh", extraArguments: [bootArg, "--hotkey", hotkey])
    }

    @objc private func runUninstall() {
        runScript(named: "uninstall.sh")
    }

    @objc private func openReadme() {
        guard let readmePath = Bundle.main.path(forResource: "README", ofType: "md") else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: readmePath))
    }

    @objc private func updateBootPreference() {
        defaults.set(bootCheckbox.state == .on, forKey: bootPreferenceKey)
    }

    private func normalizedHotkey(from value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidHotkey(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { validHotkeyCharacters.contains($0) }
    }

    private func runScript(named name: String, extraArguments: [String] = []) {
        guard let scriptPath = Bundle.main.path(forResource: name.replacingOccurrences(of: ".sh", with: ""), ofType: "sh"),
              let resourcePath = Bundle.main.resourcePath else {
            append("Unable to locate \(name) in app resources.\n")
            return
        }

        installButton.isEnabled = false
        uninstallButton.isEnabled = false
        statusLabel.stringValue = "Running \(name)..."
        append("\n$ \(name)\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "--resource-dir", resourcePath] + extraArguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.append(text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.installButton.isEnabled = true
                self?.uninstallButton.isEnabled = true
                self?.statusLabel.stringValue = proc.terminationStatus == 0 ? "Done." : "Command failed."
                self?.append("\nExit code: \(proc.terminationStatus)\n")
            }
        }

        do {
            try process.run()
        } catch {
            append("Failed to run \(name): \(error)\n")
            installButton.isEnabled = true
            uninstallButton.isEnabled = true
            statusLabel.stringValue = "Command failed."
        }
    }

    private func append(_ text: String) {
        let attr = NSAttributedString(string: text)
        outputView.textStorage?.append(attr)
        outputView.scrollToEndOfDocument(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = InstallerViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Ultra Dictation Installer"
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
