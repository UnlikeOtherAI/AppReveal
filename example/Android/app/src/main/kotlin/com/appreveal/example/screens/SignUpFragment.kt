package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.DialogFragment
import com.appreveal.example.R
import com.appreveal.example.navigation.ExampleRouter
import com.google.android.material.button.MaterialButton

class SignUpFragment : DialogFragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_signup, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val submitButton = view.findViewById<MaterialButton>(R.id.submitButton)
        val cancelButton = view.findViewById<MaterialButton>(R.id.cancelButton)

        submitButton.setOnClickListener {
            ExampleRouter.dismissModal()
            dismiss()
        }

        cancelButton.setOnClickListener {
            ExampleRouter.dismissModal()
            dismiss()
        }
    }

    override fun getTheme(): Int = com.google.android.material.R.style.ThemeOverlay_Material3_Dialog
}

/**
 * Variant that can be shown from an Activity (LoginActivity) using supportFragmentManager.
 */
class SignUpDialogFragment : DialogFragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_signup, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val submitButton = view.findViewById<MaterialButton>(R.id.submitButton)
        val cancelButton = view.findViewById<MaterialButton>(R.id.cancelButton)

        submitButton.setOnClickListener {
            ExampleRouter.dismissModal()
            dismiss()
        }

        cancelButton.setOnClickListener {
            ExampleRouter.dismissModal()
            dismiss()
        }
    }

    override fun getTheme(): Int = com.google.android.material.R.style.ThemeOverlay_Material3_Dialog
}
