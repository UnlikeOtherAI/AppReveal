import UIKit

#if DEBUG
import AppReveal
#endif

class EditProfileViewController: UIViewController {

    private let nameField = UITextField()
    private let bioField = UITextView()
    private let saveButton = UIButton(type: .system)
    private let notificationsSwitch = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Edit Profile"
        titleLabel.font = .boldSystemFont(ofSize: 24)

        nameField.text = ExampleStateContainer.shared.userName
        nameField.borderStyle = .roundedRect
        nameField.accessibilityIdentifier = "edit_profile.name"

        let bioLabel = UILabel()
        bioLabel.text = "Bio"
        bioLabel.font = .systemFont(ofSize: 14, weight: .medium)

        bioField.text = "This is a sample bio for testing."
        bioField.font = .systemFont(ofSize: 14)
        bioField.layer.borderColor = UIColor.separator.cgColor
        bioField.layer.borderWidth = 1
        bioField.layer.cornerRadius = 8
        bioField.accessibilityIdentifier = "edit_profile.bio"

        let notifLabel = UILabel()
        notifLabel.text = "Push Notifications"
        notificationsSwitch.isOn = true
        notificationsSwitch.accessibilityIdentifier = "edit_profile.notifications_toggle"

        let notifStack = UIStackView(arrangedSubviews: [notifLabel, notificationsSwitch])
        notifStack.distribution = .equalSpacing

        saveButton.setTitle("Save Changes", for: .normal)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        saveButton.backgroundColor = .systemBlue
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 8
        saveButton.accessibilityIdentifier = "edit_profile.save"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.accessibilityIdentifier = "edit_profile.cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, nameField, bioLabel, bioField,
            notifStack, saveButton, cancelButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            bioField.heightAnchor.constraint(equalToConstant: 100),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    @objc private func saveTapped() {
        ExampleStateContainer.shared.userName = nameField.text ?? ""
        dismiss(animated: true)
        ExampleRouter.shared.dismissModal()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
        ExampleRouter.shared.dismissModal()
    }
}

#if DEBUG
extension EditProfileViewController: ScreenIdentifiable {
    var screenKey: String { "profile.edit" }
    var screenTitle: String { "Edit Profile" }
    var debugMetadata: [String: Any] { [:] }
}
#endif
