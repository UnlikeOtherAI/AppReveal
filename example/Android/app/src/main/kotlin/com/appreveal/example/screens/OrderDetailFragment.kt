package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.SeekBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.appreveal.example.R
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleNetworkClient
import com.google.android.material.button.MaterialButton

class OrderDetailFragment : Fragment() {

    private var orderId: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        orderId = arguments?.getString("orderId") ?: "ORD-001"
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_order_detail, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val statusText = view.findViewById<TextView>(R.id.statusText)
        val totalText = view.findViewById<TextView>(R.id.totalText)
        val itemsText = view.findViewById<TextView>(R.id.itemsText)
        val ratingSeekBar = view.findViewById<SeekBar>(R.id.ratingSeekBar)
        val ratingValueText = view.findViewById<TextView>(R.id.ratingValueText)
        val trackButton = view.findViewById<MaterialButton>(R.id.trackButton)
        val cancelButton = view.findViewById<MaterialButton>(R.id.cancelButton)
        val reorderButton = view.findViewById<MaterialButton>(R.id.reorderButton)

        ratingSeekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                ratingValueText.text = "Rating: ${progress + 1}"
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        trackButton.setOnClickListener {
            AlertDialog.Builder(requireContext())
                .setTitle("Tracking")
                .setMessage("Shipment is in transit.")
                .setPositiveButton("OK", null)
                .show()
        }

        cancelButton.setOnClickListener {
            AlertDialog.Builder(requireContext())
                .setTitle("Cancel Order?")
                .setMessage("This cannot be undone.")
                .setPositiveButton("Yes, Cancel") { _, _ ->
                    findNavController().popBackStack()
                }
                .setNegativeButton("Keep Order", null)
                .show()
        }

        reorderButton.setOnClickListener {
            AlertDialog.Builder(requireContext())
                .setTitle("Reorder")
                .setMessage("Items added to cart.")
                .setPositiveButton("OK", null)
                .show()
        }

        // Load order detail
        ExampleNetworkClient.fetchOrderDetail(orderId) { result ->
            result.onSuccess { order ->
                statusText.text = "Status: ${order.status}"
                totalText.text = "Total: $${String.format("%.2f", order.total)}"
                itemsText.text = order.items.joinToString("\n") { "${it.name} x${it.quantity}" }
            }.onFailure {
                statusText.text = "Failed to load"
            }
        }
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("orders.detail")
    }

    override fun onPause() {
        super.onPause()
        if (isRemoving || !isVisible) {
            ExampleRouter.pop()
        }
    }
}
