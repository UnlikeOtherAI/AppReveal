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
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.appreveal.example.R
import com.appreveal.example.models.ExampleProduct
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleNetworkClient
import com.google.android.material.button.MaterialButton

class CatalogFragment : Fragment() {

    private var products: List<ExampleProduct> = emptyList()
    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ProductsAdapter

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_catalog, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        recyclerView = view.findViewById(R.id.catalogRecyclerView)

        adapter = ProductsAdapter(
            onProductClick = { product ->
                val bundle = Bundle().apply { putString("productId", product.id) }
                findNavController().navigate(R.id.action_catalog_to_product_detail, bundle)
            },
            onAddToCart = { product ->
                Toast.makeText(requireContext(), "${product.name} added to cart", Toast.LENGTH_SHORT).show()
            }
        )
        recyclerView.layoutManager = GridLayoutManager(requireContext(), 2)
        recyclerView.adapter = adapter

        val cartButton = view.findViewById<ImageButton>(R.id.cartButton)
        cartButton.setOnClickListener {
            ExampleRouter.presentModal("cart.main")
            CartFragment().show(parentFragmentManager, "cart")
        }

        loadProducts()
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("catalog.list")
    }

    private fun loadProducts() {
        ExampleNetworkClient.fetchProducts { result ->
            result.onSuccess { fetched ->
                products = fetched
                adapter.submitList(products)
            }
        }
    }

    // --- Adapter ---

    private class ProductsAdapter(
        private val onProductClick: (ExampleProduct) -> Unit,
        private val onAddToCart: (ExampleProduct) -> Unit
    ) : RecyclerView.Adapter<ProductsAdapter.ViewHolder>() {

        private var items: List<ExampleProduct> = emptyList()

        fun submitList(list: List<ExampleProduct>) {
            items = list
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_product, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val product = items[position]
            holder.bind(product, position)
            holder.itemView.setOnClickListener { onProductClick(product) }
            holder.addToCartButton.setOnClickListener { onAddToCart(product) }
        }

        override fun getItemCount(): Int = items.size

        class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            private val icon: ImageView = view.findViewById(R.id.productIcon)
            private val name: TextView = view.findViewById(R.id.productName)
            private val price: TextView = view.findViewById(R.id.productPrice)
            val addToCartButton: MaterialButton = view.findViewById(R.id.addToCartButton)

            fun bind(product: ExampleProduct, index: Int) {
                itemView.tag = "catalog.product_$index"
                addToCartButton.tag = "catalog.add_to_cart_$index"
                name.text = product.name
                price.text = "$${String.format("%.2f", product.price)}"

                val resId = itemView.context.resources.getIdentifier(
                    product.iconResName, "drawable", "android"
                )
                if (resId != 0) {
                    icon.setImageResource(resId)
                } else {
                    icon.setImageResource(android.R.drawable.ic_menu_gallery)
                }
            }
        }
    }
}
