import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'orders.detail';

  @override
  String get screenTitle => widget.order['id'] as String;

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.order['id'] as String)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Order ID', widget.order['id'] as String, key: const ValueKey('order.id')),
            _row('Date', widget.order['date'] as String, key: const ValueKey('order.date')),
            _row('Status', widget.order['status'] as String, key: const ValueKey('order.status')),
            _row('Total', '\$${widget.order['total']}', key: const ValueKey('order.total')),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('order.track'),
              onPressed: () {},
              child: const Text('Track Package'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      key: key,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value),
      ],
    ),
  );
}
