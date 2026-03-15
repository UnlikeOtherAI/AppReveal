import UIKit

#if DEBUG
import AppReveal
#endif

class LoginViewController: UIViewController {

    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let forgotPasswordButton = UIButton(type: .system)
    private let signUpButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let logoImageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Logo
        logoImageView.image = UIImage(systemName: "shield.checkered")
        logoImageView.tintColor = .systemBlue
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.accessibilityIdentifier = "login.logo"

        // Email
        emailField.placeholder = "Email address"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.accessibilityIdentifier = "login.email"

        // Password
        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.accessibilityIdentifier = "login.password"

        // Login button
        loginButton.setTitle("Log In", for: .normal)
        loginButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        loginButton.backgroundColor = .systemBlue
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.layer.cornerRadius = 8
        loginButton.accessibilityIdentifier = "login.submit"
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        // Forgot password
        forgotPasswordButton.setTitle("Forgot Password?", for: .normal)
        forgotPasswordButton.accessibilityIdentifier = "login.forgot_password"
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        // Sign up
        signUpButton.setTitle("Create Account", for: .normal)
        signUpButton.accessibilityIdentifier = "login.sign_up"
        signUpButton.addTarget(self, action: #selector(signUpTapped), for: .touchUpInside)

        // Error label
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.accessibilityIdentifier = "login.error"

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.accessibilityIdentifier = "login.loading"

        // Layout
        let stack = UIStackView(arrangedSubviews: [
            logoImageView, emailField, passwordField,
            errorLabel, loginButton, forgotPasswordButton, signUpButton, activityIndicator
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            logoImageView.heightAnchor.constraint(equalToConstant: 80),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    @objc private func loginTapped() {
        errorLabel.isHidden = true
        activityIndicator.startAnimating()
        loginButton.isEnabled = false

        let email = emailField.text ?? ""
        let password = passwordField.text ?? ""

        ExampleNetworkClient.shared.login(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.loginButton.isEnabled = true

                switch result {
                case .success:
                    ExampleStateContainer.shared.isLoggedIn = true
                    ExampleStateContainer.shared.userEmail = email
                    self?.dismiss(animated: true)
                case .failure(let error):
                    self?.errorLabel.text = error.localizedDescription
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }

    @objc private func forgotPasswordTapped() {
        let alert = UIAlertController(
            title: "Reset Password",
            message: "Enter your email to receive a reset link.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Email"
            tf.text = self.emailField.text
            tf.accessibilityIdentifier = "login.reset_email"
        }
        alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
            // Simulate sending reset email
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func signUpTapped() {
        let signUpVC = SignUpViewController()
        signUpVC.modalPresentationStyle = .pageSheet
        present(signUpVC, animated: true)
        ExampleRouter.shared.presentModal(route: "auth.signup")
    }
}

#if DEBUG
extension LoginViewController: ScreenIdentifiable {
    var screenKey: String { "auth.login" }
    var screenTitle: String { "Login" }
    var debugMetadata: [String: Any] { ["hasEmailInput": !(emailField.text?.isEmpty ?? true)] }
}
#endif
