import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_state_container.dart';
import '../services/example_network_client.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'catalog.detail';

  @override
  String get screenTitle => widget.product['name'] as String;

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
    ExampleNetworkClient.instance.capture(
      method: 'GET',
      url: 'https://api.example.com/products/${widget.product['id']}',
      statusCode: 200,
      duration: 0.183,
    );
  }

  void _addToCart() {
    ExampleStateContainer.instance.cartItemCount++;
    ExampleNetworkClient.instance.capture(
      method: 'POST',
      url: 'https://api.example.com/cart/items',
      statusCode: 201,
      duration: 0.234,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.product['name']} added to cart')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product['name'] as String)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('product.image'),
              height: 200,
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.image, size: 80, color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            Text(
              key: const ValueKey('product.name'),
              widget.product['name'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              key: const ValueKey('product.price'),
              '\$${widget.product['price']}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              key: const ValueKey('product.category'),
              'Category: ${widget.product['category']}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('product.add_to_cart'),
                onPressed: _addToCart,
                child: const Text('Add to Cart'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
