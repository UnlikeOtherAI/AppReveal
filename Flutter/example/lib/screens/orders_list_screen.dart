import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'orders.list';

  @override
  String get screenTitle => 'Orders';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  final _orders = [
    {'id': 'ORD-001', 'date': '2024-03-01', 'status': 'Delivered', 'total': 149.99},
    {'id': 'ORD-002', 'date': '2024-03-08', 'status': 'Shipped', 'total': 79.95},
    {'id': 'ORD-003', 'date': '2024-03-12', 'status': 'Processing', 'total': 299.00},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: ListView.builder(
        key: const ValueKey('orders.list'),
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(
            key: ValueKey('orders.item.${order['id']}'),
            title: Text(order['id'] as String),
            subtitle: Text('${order['date']} · ${order['status']}'),
            trailing: Text('\$${order['total']}'),
            onTap: () => Navigator.of(context).pushNamed('/orders/detail', arguments: order),
          );
        },
      ),
    );
  }
}
