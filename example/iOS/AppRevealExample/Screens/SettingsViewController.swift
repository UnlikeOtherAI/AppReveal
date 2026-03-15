import UIKit

class SettingsViewController: UITableViewController {

    private struct Setting {
        let id: String
        let title: String
        let type: SettingType

        enum SettingType {
            case toggle(Bool)
            case detail(String)
            case action
        }
    }

    private let sections: [(title: String, items: [Setting])] = [
        ("Appearance", [
            Setting(id: "settings.dark_mode", title: "Dark Mode", type: .toggle(false)),
            Setting(id: "settings.large_text", title: "Large Text", type: .toggle(false)),
            Setting(id: "settings.reduce_motion", title: "Reduce Motion", type: .toggle(false)),
        ]),
        ("Notifications", [
            Setting(id: "settings.push_enabled", title: "Push Notifications", type: .toggle(true)),
            Setting(id: "settings.email_enabled", title: "Email Notifications", type: .toggle(true)),
            Setting(id: "settings.sound_enabled", title: "Sound", type: .toggle(true)),
        ]),
        ("Account", [
            Setting(id: "settings.change_password", title: "Change Password", type: .action),
            Setting(id: "settings.privacy", title: "Privacy Policy", type: .detail("View")),
            Setting(id: "settings.terms", title: "Terms of Service", type: .detail("View")),
            Setting(id: "settings.app_version", title: "App Version", type: .detail("1.0.0")),
        ]),
        ("Danger Zone", [
            Setting(id: "settings.clear_cache", title: "Clear Cache", type: .action),
            Setting(id: "settings.delete_account", title: "Delete Account", type: .action),
        ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.accessibilityIdentifier = "settings.table"

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "settings.main")
    }

    // MARK: - Table view

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = sections[indexPath.section].items[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = setting.title
        cell.accessibilityIdentifier = setting.id

        switch setting.type {
        case .toggle(let isOn):
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.accessibilityIdentifier = "\(setting.id)_toggle"
            cell.accessoryView = toggle
        case .detail(let value):
            cell.detailTextLabel?.text = value
            cell.accessoryType = .disclosureIndicator
        case .action:
            cell.textLabel?.textColor = setting.id.contains("delete") ? .systemRed : .systemBlue
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let setting = sections[indexPath.section].items[indexPath.row]

        if setting.id == "settings.delete_account" {
            let alert = UIAlertController(
                title: "Delete Account",
                message: "This action is permanent and cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }
}
