package com.appreveal.example.screens

import android.content.Intent
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
import com.appreveal.example.services.ExampleStateContainer
import com.google.android.material.button.MaterialButton
import com.google.android.material.tabs.TabLayout

class ProfileFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_profile, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val nameText = view.findViewById<TextView>(R.id.nameText)
        val emailText = view.findViewById<TextView>(R.id.emailText)
        val memberSinceText = view.findViewById<TextView>(R.id.memberSinceText)
        val orderCountText = view.findViewById<TextView>(R.id.orderCountText)
        val tabSelector = view.findViewById<TabLayout>(R.id.tabSelector)
        val editButton = view.findViewById<MaterialButton>(R.id.editButton)
        val logoutButton = view.findViewById<MaterialButton>(R.id.logoutButton)

        // Add tabs
        tabSelector.addTab(tabSelector.newTab().setText("Activity"))
        tabSelector.addTab(tabSelector.newTab().setText("Favorites"))

        // Load profile data
        nameText.text = ExampleStateContainer.userName
        emailText.text = ExampleStateContainer.userEmail
        memberSinceText.text = "Member since Jan 2024"
        orderCountText.text = "12 orders placed"

        editButton.setOnClickListener {
            ExampleRouter.presentModal("profile.edit")
            findNavController().navigate(R.id.action_profile_to_edit)
        }

        logoutButton.setOnClickListener {
            AlertDialog.Builder(requireContext())
                .setTitle("Log Out?")
                .setPositiveButton("Log Out") { _, _ ->
                    ExampleStateContainer.isLoggedIn = false
                    startActivity(Intent(requireContext(), LoginActivity::class.java))
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("profile.main")
    }
}
