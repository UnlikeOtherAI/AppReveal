import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/orders_list_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/webview_demo_screen.dart';
import 'widgets/main_shell.dart';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppReveal Example',
      navigatorObservers: [AppReveal.navigatorObserver],
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/main': (_) => const MainShell(),
        '/catalog/detail': (ctx) => ProductDetailScreen(
          product: ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>,
        ),
        '/orders': (_) => const OrdersListScreen(),
        '/orders/detail': (ctx) => OrderDetailScreen(
          order: ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>,
        ),
        '/profile/edit': (_) => const EditProfileScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/webview': (_) => const WebViewDemoScreen(),
      },
    );
  }
}
