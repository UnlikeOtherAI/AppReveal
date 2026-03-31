import AppKit

final class SettingsViewController: NSViewController {

    private let notificationsSwitch = NSSwitch()
    private let themePopup = NSPopUpButton()
    private let endpointField = NSTextField(string: "https://api.example.com")
    private let saveButton = NSButton(title: "Save Settings", target: nil, action: nil)

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    private func configureUI() {
        let notificationsLabel = NSTextField(labelWithString: "Notifications")
        let themeLabel = NSTextField(labelWithString: "Theme")
        let endpointLabel = NSTextField(labelWithString: "API Endpoint")

        notificationsSwitch.state = .on
        notificationsSwitch.setAccessibilityIdentifier("settings.notifications")

        themePopup.addItems(withTitles: ["System", "Light", "Dark"])
        themePopup.selectItem(withTitle: "System")
        themePopup.setAccessibilityIdentifier("settings.theme")

        endpointField.setAccessibilityIdentifier("settings.endpoint")
        endpointField.lineBreakMode = .byTruncatingMiddle

        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        saveButton.bezelStyle = .rounded
        saveButton.setAccessibilityIdentifier("settings.save_button")

        let grid = NSGridView(views: [
            [notificationsLabel, notificationsSwitch],
            [themeLabel, themePopup],
            [endpointLabel, endpointField],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 16

        let stack = NSStackView(views: [grid, saveButton])
        stack.orientation = .vertical
        stack.spacing = 18
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            endpointField.widthAnchor.constraint(equalToConstant: 320),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
        ])
    }

    @objc private func saveSettings() {
        let theme = themePopup.selectedItem?.title ?? "System"
        let notificationsEnabled = notificationsSwitch.state == .on
        let endpoint = endpointField.stringValue

        ExampleNetworkClient.shared.saveSettings(endpoint: endpoint, notificationsEnabled: notificationsEnabled, theme: theme) { [weak self] _ in
            guard let self else { return }

            let alert = NSAlert()
            alert.messageText = "Settings Saved"
            alert.informativeText = "Endpoint: \(endpoint)\nTheme: \(theme)"
            alert.addButton(withTitle: "OK")

            if let window = self.view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}
