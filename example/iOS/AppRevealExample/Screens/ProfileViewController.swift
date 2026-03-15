import UIKit

class ProfileViewController: UIViewController {

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let emailLabel = UILabel()
    private let editButton = UIButton(type: .system)
    private let logoutButton = UIButton(type: .system)
    private let memberSinceLabel = UILabel()
    private let orderCountLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: ["Activity", "Favorites", "Reviews"])

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        setupUI()
        loadProfile()

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "profile.main")
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = .systemBlue
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.accessibilityIdentifier = "profile.avatar"

        nameLabel.font = .boldSystemFont(ofSize: 22)
        nameLabel.textAlignment = .center
        nameLabel.accessibilityIdentifier = "profile.name"

        emailLabel.font = .systemFont(ofSize: 14)
        emailLabel.textColor = .secondaryLabel
        emailLabel.textAlignment = .center
        emailLabel.accessibilityIdentifier = "profile.email"

        memberSinceLabel.font = .systemFont(ofSize: 12)
        memberSinceLabel.textColor = .tertiaryLabel
        memberSinceLabel.textAlignment = .center
        memberSinceLabel.accessibilityIdentifier = "profile.member_since"

        orderCountLabel.font = .systemFont(ofSize: 14)
        orderCountLabel.textAlignment = .center
        orderCountLabel.accessibilityIdentifier = "profile.order_count"

        editButton.setTitle("Edit Profile", for: .normal)
        editButton.accessibilityIdentifier = "profile.edit"
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        logoutButton.setTitle("Log Out", for: .normal)
        logoutButton.setTitleColor(.systemRed, for: .normal)
        logoutButton.accessibilityIdentifier = "profile.logout"
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.accessibilityIdentifier = "profile.tab_selector"

        let stack = UIStackView(arrangedSubviews: [
            avatarImageView, nameLabel, emailLabel,
            memberSinceLabel, orderCountLabel,
            segmentedControl, editButton, logoutButton
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            avatarImageView.heightAnchor.constraint(equalToConstant: 100),
            avatarImageView.widthAnchor.constraint(equalToConstant: 100),
            segmentedControl.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func loadProfile() {
        let state = ExampleStateContainer.shared
        nameLabel.text = state.userName
        emailLabel.text = state.userEmail
        memberSinceLabel.text = "Member since Jan 2024"
        orderCountLabel.text = "12 orders placed"
    }

    @objc private func editTapped() {
        let editVC = EditProfileViewController()
        editVC.modalPresentationStyle = .pageSheet
        present(editVC, animated: true)
        ExampleRouter.shared.presentModal(route: "profile.edit")
    }

    @objc private func logoutTapped() {
        let alert = UIAlertController(title: "Log Out?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
            ExampleStateContainer.shared.isLoggedIn = false
            let loginVC = LoginViewController()
            loginVC.modalPresentationStyle = .fullScreen
            self.present(loginVC, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
