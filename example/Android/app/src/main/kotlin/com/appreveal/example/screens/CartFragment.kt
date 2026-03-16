package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.DialogFragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.appreveal.example.R
import com.appreveal.example.models.ExampleProduct
import com.appreveal.example.navigation.ExampleRouter
import com.google.android.material.button.MaterialButton

class CartFragment : DialogFragment() {

    data class CartItem(val product: ExampleProduct, val quantity: Int)

    private val cartItems = mutableListOf(
        CartItem(ExampleProduct.samples[0], 2),
        CartItem(ExampleProduct.samples[1], 1)
    )

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_cart, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val recyclerView = view.findViewById<RecyclerView>(R.id.cartRecyclerView)
        val emptyMessage = view.findViewById<TextView>(R.id.emptyMessage)
        val totalText = view.findViewById<TextView>(R.id.totalText)
        val checkoutButton = view.findViewById<MaterialButton>(R.id.checkoutButton)
        val closeButton = view.findViewById<ImageButton>(R.id.closeButton)

        val adapter = CartAdapter(cartItems)
        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        emptyMessage.visibility = if (cartItems.isEmpty()) View.VISIBLE else View.GONE

        val total = cartItems.sumOf { it.product.price * it.quantity }
        totalText.text = "Total: $${String.format("%.2f", total)}"

        checkoutButton.setOnClickListener {
            Toast.makeText(requireContext(), "Checkout initiated", Toast.LENGTH_SHORT).show()
        }

        closeButton.setOnClickListener {
            ExampleRouter.dismissModal()
            dismiss()
        }
    }

    override fun getTheme(): Int = com.google.android.material.R.style.ThemeOverlay_Material3_Dialog

    // --- Adapter ---

    private class CartAdapter(
        private val items: List<CartItem>
    ) : RecyclerView.Adapter<CartAdapter.ViewHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_cart, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val item = items[position]
            holder.bind(item, position)
        }

        override fun getItemCount(): Int = items.size

        class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            private val nameText: TextView = view.findViewById(R.id.cartItemName)
            private val quantityText: TextView = view.findViewById(R.id.cartItemQuantity)

            fun bind(item: CartItem, index: Int) {
                itemView.tag = "cart.item_$index"
                nameText.text = item.product.name
                quantityText.text = "x${item.quantity}"
            }
        }
    }
}
