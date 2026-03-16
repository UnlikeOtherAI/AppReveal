package com.appreveal.example.screens

import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.appreveal.example.R
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleNetworkClient
import com.appreveal.example.services.ExampleStateContainer
import com.google.android.material.button.MaterialButton

class LoginActivity : AppCompatActivity() {

    private lateinit var emailField: EditText
    private lateinit var passwordField: EditText
    private lateinit var loginButton: MaterialButton
    private lateinit var errorLabel: TextView
    private lateinit var loadingIndicator: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.fragment_login)

        emailField = findViewById(R.id.emailField)
        passwordField = findViewById(R.id.passwordField)
        loginButton = findViewById(R.id.loginButton)
        errorLabel = findViewById(R.id.errorLabel)
        loadingIndicator = findViewById(R.id.loadingIndicator)

        val logoImageView = findViewById<ImageView>(R.id.logoImageView)
        logoImageView.tag = "login.logo"
        emailField.tag = "login.email"
        passwordField.tag = "login.password"
        loginButton.tag = "login.submit"
        errorLabel.tag = "login.error"
        loadingIndicator.tag = "login.loading"

        loginButton.setOnClickListener { loginTapped() }

        val forgotPasswordButton = findViewById<MaterialButton>(R.id.forgotPasswordButton)
        forgotPasswordButton.tag = "login.forgot_password"
        forgotPasswordButton.setOnClickListener { forgotPasswordTapped() }

        val signUpButton = findViewById<MaterialButton>(R.id.signUpButton)
        signUpButton.tag = "login.sign_up"
        signUpButton.setOnClickListener { signUpTapped() }
    }

    private fun loginTapped() {
        errorLabel.visibility = View.GONE
        loadingIndicator.visibility = View.VISIBLE
        loginButton.isEnabled = false

        val email = emailField.text.toString()
        val password = passwordField.text.toString()

        ExampleNetworkClient.login(email, password) { result ->
            loadingIndicator.visibility = View.GONE
            loginButton.isEnabled = true

            result.onSuccess {
                ExampleStateContainer.isLoggedIn = true
                ExampleStateContainer.userEmail = email
                finish()
            }.onFailure { error ->
                errorLabel.text = error.message
                errorLabel.visibility = View.VISIBLE
            }
        }
    }

    private fun forgotPasswordTapped() {
        val input = EditText(this).apply {
            hint = "Email"
            setText(emailField.text)
            tag = "login.reset_email"
        }

        AlertDialog.Builder(this)
            .setTitle("Reset Password")
            .setMessage("Enter your email to receive a reset link.")
            .setView(input)
            .setPositiveButton("Send") { _, _ -> /* Simulate sending */ }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun signUpTapped() {
        ExampleRouter.presentModal("auth.signup")
        SignUpDialogFragment().show(supportFragmentManager, "signup")
    }
}
