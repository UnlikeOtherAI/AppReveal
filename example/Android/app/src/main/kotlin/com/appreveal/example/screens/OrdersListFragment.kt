package com.appreveal.example.screens

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.widget.SearchView
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.appreveal.example.R
import com.appreveal.example.models.ExampleOrder
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleNetworkClient

class OrdersListFragment : Fragment() {

    private var orders: List<ExampleOrder> = emptyList()
    private lateinit var recyclerView: RecyclerView
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var adapter: OrdersAdapter

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_orders_list, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        swipeRefresh = view.findViewById(R.id.swipeRefresh)
        recyclerView = view.findViewById(R.id.ordersRecyclerView)

        adapter = OrdersAdapter { order ->
            val bundle = Bundle().apply { putString("orderId", order.id) }
            findNavController().navigate(R.id.action_orders_to_detail, bundle)
        }
        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        swipeRefresh.setOnRefreshListener { loadOrders() }

        loadOrders()
    }

    override fun onResume() {
        super.onResume()
        ExampleRouter.push("orders.list")
    }

    private fun loadOrders() {
        ExampleNetworkClient.fetchOrders { result ->
            swipeRefresh.isRefreshing = false
            result.onSuccess { fetchedOrders ->
                orders = fetchedOrders
                adapter.submitList(orders)
            }
        }
    }

    // --- Adapter ---

    private class OrdersAdapter(
        private val onClick: (ExampleOrder) -> Unit
    ) : RecyclerView.Adapter<OrdersAdapter.ViewHolder>() {

        private var items: List<ExampleOrder> = emptyList()

        fun submitList(list: List<ExampleOrder>) {
            items = list
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_order, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val order = items[position]
            holder.bind(order, position)
            holder.itemView.setOnClickListener { onClick(order) }
        }

        override fun getItemCount(): Int = items.size

        class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            private val idText: TextView = view.findViewById(R.id.orderIdText)
            private val detailText: TextView = view.findViewById(R.id.orderDetailText)

            fun bind(order: ExampleOrder, index: Int) {
                itemView.tag = "orders.cell_$index"
                idText.text = "Order #${order.id}"
                detailText.text = "${order.status} - $${String.format("%.2f", order.total)}"
            }
        }
    }
}
