package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.appreveal.example.R
import com.appreveal.example.navigation.ExampleRouter
import com.google.android.material.button.MaterialButton

class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_settings, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val deleteAccountButton = view.findViewById<MaterialButton>(R.id.deleteAccountButton)
        val tapCalibrationButton = view.findViewById<TextView>(R.id.tapCalibrationButton)

        deleteAccountButton.setOnClickListener {
            AlertDialog.Builder(requireContext())
                .setTitle("Delete Account")
                .setMessage("This action is permanent and cannot be undone.")
                .setPositiveButton("Delete") { _, _ ->
                    // Simulate account deletion
                }
                .setNegativeButton("Cancel", null)
                .show()
        }

        tapCalibrationButton.setOnClickListener {
            findNavController().navigate(R.id.action_settings_to_tap_calibration)
        }
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("settings.main")
    }
}
