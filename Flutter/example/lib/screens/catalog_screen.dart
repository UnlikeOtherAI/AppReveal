import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_network_client.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'catalog.list';

  @override
  String get screenTitle => 'Catalog';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
    ExampleNetworkClient.instance.capture(
      method: 'GET',
      url: 'https://api.example.com/catalog?page=1',
      statusCode: 200,
      duration: 0.287,
    );
  }

  final _products = [
    {'id': 'p1', 'name': 'Wireless Headphones', 'price': 99.99, 'category': 'Electronics'},
    {'id': 'p2', 'name': 'Running Shoes', 'price': 149.00, 'category': 'Sports'},
    {'id': 'p3', 'name': 'Coffee Maker', 'price': 79.95, 'category': 'Kitchen'},
    {'id': 'p4', 'name': 'Yoga Mat', 'price': 34.99, 'category': 'Sports'},
    {'id': 'p5', 'name': 'Desk Lamp', 'price': 45.00, 'category': 'Home'},
    {'id': 'p6', 'name': 'Water Bottle', 'price': 24.99, 'category': 'Sports'},
    {'id': 'p7', 'name': 'Smart Watch', 'price': 299.00, 'category': 'Electronics'},
    {'id': 'p8', 'name': 'Backpack', 'price': 89.00, 'category': 'Travel'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog'),
        actions: [
          IconButton(
            key: const ValueKey('catalog.search'),
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView.builder(
        key: const ValueKey('catalog.list'),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return ListTile(
            key: ValueKey('catalog.item.${product['id']}'),
            title: Text(product['name'] as String),
            subtitle: Text(product['category'] as String),
            trailing: Text('\$${product['price']}'),
            onTap: () => Navigator.of(context).pushNamed(
              '/catalog/detail',
              arguments: product,
            ),
          );
        },
      ),
    );
  }
}
