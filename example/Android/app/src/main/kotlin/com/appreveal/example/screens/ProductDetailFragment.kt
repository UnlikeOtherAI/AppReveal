package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import com.appreveal.example.R
import com.appreveal.example.models.ExampleProduct
import com.appreveal.example.navigation.ExampleRouter
import com.google.android.material.button.MaterialButton

class ProductDetailFragment : Fragment() {

    private var productId: String = ""
    private var quantity: Int = 1
    private var isFavorite: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        productId = arguments?.getString("productId") ?: "PROD-001"
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_product_detail, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val product = ExampleProduct.samples.firstOrNull { it.id == productId }
            ?: ExampleProduct.samples[0]

        val productImage = view.findViewById<ImageView>(R.id.productImage)
        val productName = view.findViewById<TextView>(R.id.productName)
        val productPrice = view.findViewById<TextView>(R.id.productPrice)
        val productDescription = view.findViewById<TextView>(R.id.productDescription)
        val quantityLabel = view.findViewById<TextView>(R.id.quantityLabel)
        val decreaseButton = view.findViewById<MaterialButton>(R.id.decreaseButton)
        val increaseButton = view.findViewById<MaterialButton>(R.id.increaseButton)
        val addToCartButton = view.findViewById<MaterialButton>(R.id.addToCartButton)
        val favoriteButton = view.findViewById<ImageButton>(R.id.favoriteButton)

        productName.text = product.name
        productPrice.text = "$${String.format("%.2f", product.price)}"
        productDescription.text = product.description
        quantityLabel.text = "Qty: $quantity"

        val resId = requireContext().resources.getIdentifier(
            product.iconResName, "drawable", "android"
        )
        if (resId != 0) {
            productImage.setImageResource(resId)
        } else {
            productImage.setImageResource(android.R.drawable.ic_menu_gallery)
        }

        decreaseButton.setOnClickListener {
            if (quantity > 1) {
                quantity--
                quantityLabel.text = "Qty: $quantity"
            }
        }

        increaseButton.setOnClickListener {
            if (quantity < 99) {
                quantity++
                quantityLabel.text = "Qty: $quantity"
            }
        }

        addToCartButton.setOnClickListener {
            Toast.makeText(
                requireContext(),
                "${product.name} x$quantity added to cart",
                Toast.LENGTH_SHORT
            ).show()
        }

        favoriteButton.setOnClickListener {
            isFavorite = !isFavorite
            favoriteButton.setImageResource(
                if (isFavorite) android.R.drawable.btn_star_big_on
                else android.R.drawable.btn_star_big_off
            )
        }
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("catalog.detail")
    }

    override fun onPause() {
        super.onPause()
        if (isRemoving || !isVisible) {
            ExampleRouter.pop()
        }
    }
}
