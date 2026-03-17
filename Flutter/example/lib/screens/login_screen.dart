import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_state_container.dart';
import '../services/example_network_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with ScreenIdentifiable {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  String get screenKey => 'auth.login';

  @override
  String get screenTitle => 'Login';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    ExampleNetworkClient.instance.capture(
      method: 'POST',
      url: 'https://api.example.com/auth/login',
      statusCode: 200,
      duration: 0.412,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    ExampleStateContainer.instance
      ..isLoggedIn = true
      ..userEmail = _emailController.text.isNotEmpty ? _emailController.text : 'demo@example.com'
      ..userName = 'Demo User';
    if (mounted) {
      setState(() => _loading = false);
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FlutterLogo(size: 72),
            const SizedBox(height: 32),
            TextField(
              key: const ValueKey('login.email'),
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('login.password'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('login.submit'),
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign In'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('login.signup_link'),
              onPressed: () => Navigator.of(context).pushNamed('/signup'),
              child: const Text("Don't have an account? Sign up"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
