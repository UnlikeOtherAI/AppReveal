package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.appreveal.example.R
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleStateContainer
import com.google.android.material.button.MaterialButton

class EditProfileFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_edit_profile, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val nameField = view.findViewById<EditText>(R.id.nameField)
        val bioField = view.findViewById<EditText>(R.id.bioField)
        val saveButton = view.findViewById<MaterialButton>(R.id.saveButton)
        val cancelButton = view.findViewById<MaterialButton>(R.id.cancelButton)

        nameField.setText(ExampleStateContainer.userName)
        bioField.setText("This is a sample bio for testing.")

        saveButton.setOnClickListener {
            ExampleStateContainer.userName = nameField.text.toString()
            ExampleRouter.dismissModal()
            findNavController().popBackStack()
        }

        cancelButton.setOnClickListener {
            ExampleRouter.dismissModal()
            findNavController().popBackStack()
        }
    }
}
