import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_state_container.dart';
import '../services/example_network_client.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'cart.main';

  @override
  String get screenTitle => 'Cart';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  final _items = [
    {'name': 'Wireless Headphones', 'price': 99.99, 'qty': 1},
    {'name': 'Yoga Mat', 'price': 34.99, 'qty': 2},
  ];

  double get _total => _items.fold(
    0, (sum, item) => sum + (item['price'] as double) * (item['qty'] as int),
  );

  void _checkout() {
    ExampleNetworkClient.instance.capture(
      method: 'POST',
      url: 'https://api.example.com/checkout',
      statusCode: 200,
      duration: 0.567,
    );
    ExampleStateContainer.instance.cartItemCount = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('cart.order_confirmed'),
        title: const Text('Order Confirmed'),
        content: const Text('Your order has been placed successfully.'),
        actions: [
          TextButton(
            key: const ValueKey('cart.ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              key: const ValueKey('cart.items'),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  key: ValueKey('cart.item.$index'),
                  title: Text(item['name'] as String),
                  subtitle: Text('Qty: ${item['qty']}'),
                  trailing: Text('\$${((item['price'] as double) * (item['qty'] as int)).toStringAsFixed(2)}'),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(
                      key: const ValueKey('cart.total'),
                      '\$${_total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const ValueKey('cart.checkout'),
                    onPressed: _checkout,
                    child: const Text('Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
