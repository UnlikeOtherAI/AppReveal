import AppKit

final class ProfileViewController: NSViewController {

    private let nameLabel = NSTextField(labelWithString: "")
    private let emailLabel = NSTextField(labelWithString: "")
    private let membershipLabel = NSTextField(labelWithString: "")
    private let categoryLabel = NSTextField(labelWithString: "")
    private let editButton = NSButton(title: "Edit Profile", target: nil, action: nil)

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        loadProfile()
    }

    private func configureUI() {
        let avatar = NSImageView(image: NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "Profile") ?? NSImage())
        avatar.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        avatar.contentTintColor = .controlAccentColor

        nameLabel.font = .boldSystemFont(ofSize: 26)
        nameLabel.setAccessibilityIdentifier("profile.name")

        emailLabel.textColor = .secondaryLabelColor
        emailLabel.setAccessibilityIdentifier("profile.email")

        membershipLabel.textColor = .secondaryLabelColor
        categoryLabel.textColor = .secondaryLabelColor

        editButton.target = self
        editButton.action = #selector(editProfile)
        editButton.bezelStyle = .rounded
        editButton.setAccessibilityIdentifier("profile.edit_button")

        let stack = NSStackView(views: [avatar, nameLabel, emailLabel, membershipLabel, categoryLabel, editButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            avatar.heightAnchor.constraint(equalToConstant: 96),
            avatar.widthAnchor.constraint(equalToConstant: 96),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func loadProfile() {
        ExampleNetworkClient.shared.fetchProfile { [weak self] result in
            guard let self else { return }
            if case .success(let profile) = result {
                self.nameLabel.stringValue = profile.name
                self.emailLabel.stringValue = profile.email
                self.membershipLabel.stringValue = profile.membership
                self.categoryLabel.stringValue = "Favorite category: \(profile.favoriteCategory)"
                ExampleStateContainer.shared.userName = profile.name
                ExampleStateContainer.shared.userEmail = profile.email
            }
        }
    }

    @objc private func editProfile() {
        let modalRoute = "profile.edit"
        ExampleRouter.shared.presentModal(route: modalRoute)

        let alert = NSAlert()
        alert.messageText = "Edit Profile"
        alert.informativeText = "This example keeps editing lightweight and tracks the modal in AppReveal."
        alert.addButton(withTitle: "Done")

        if let window = view.window {
            alert.beginSheetModal(for: window) { _ in
                ExampleRouter.shared.dismissModal(route: modalRoute)
            }
        } else {
            alert.runModal()
            ExampleRouter.shared.dismissModal(route: modalRoute)
        }
    }
}
