import UIKit

#if DEBUG
import AppReveal
#endif

class SignUpViewController: UIViewController {

    private let nameField = UITextField()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let confirmPasswordField = UITextField()
    private let termsSwitch = UISwitch()
    private let signUpButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Create Account"

        nameField.placeholder = "Full Name"
        nameField.borderStyle = .roundedRect
        nameField.accessibilityIdentifier = "signup.name"

        emailField.placeholder = "Email"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.accessibilityIdentifier = "signup.email"

        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.accessibilityIdentifier = "signup.password"

        confirmPasswordField.placeholder = "Confirm Password"
        confirmPasswordField.borderStyle = .roundedRect
        confirmPasswordField.isSecureTextEntry = true
        confirmPasswordField.accessibilityIdentifier = "signup.confirm_password"

        let termsLabel = UILabel()
        termsLabel.text = "I agree to the Terms"
        termsLabel.font = .systemFont(ofSize: 14)
        termsSwitch.accessibilityIdentifier = "signup.terms_toggle"

        let termsStack = UIStackView(arrangedSubviews: [termsSwitch, termsLabel])
        termsStack.spacing = 8

        signUpButton.setTitle("Create Account", for: .normal)
        signUpButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        signUpButton.backgroundColor = .systemGreen
        signUpButton.setTitleColor(.white, for: .normal)
        signUpButton.layer.cornerRadius = 8
        signUpButton.accessibilityIdentifier = "signup.submit"
        signUpButton.addTarget(self, action: #selector(signUpTapped), for: .touchUpInside)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Cancel", for: .normal)
        closeButton.accessibilityIdentifier = "signup.cancel"
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            nameField, emailField, passwordField,
            confirmPasswordField, termsStack, signUpButton, closeButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            signUpButton.heightAnchor.constraint(equalToConstant: 50),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    @objc private func signUpTapped() {
        dismiss(animated: true)
        ExampleRouter.shared.dismissModal()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
        ExampleRouter.shared.dismissModal()
    }
}

#if DEBUG
extension SignUpViewController: ScreenIdentifiable {
    var screenKey: String { "auth.signup" }
    var screenTitle: String { "Sign Up" }
    var debugMetadata: [String: Any] { [:] }
}
#endif
