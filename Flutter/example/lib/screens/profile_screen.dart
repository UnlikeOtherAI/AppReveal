import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_state_container.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'profile.main';

  @override
  String get screenTitle => 'Profile';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  @override
  Widget build(BuildContext context) {
    final state = ExampleStateContainer.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            key: const ValueKey('profile.settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          const CircleAvatar(
            key: ValueKey('profile.avatar'),
            radius: 48,
            child: Icon(Icons.person, size: 48),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              key: const ValueKey('profile.name'),
              state.userName.isNotEmpty ? state.userName : 'Demo User',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Center(
            child: Text(
              key: const ValueKey('profile.email'),
              state.userEmail.isNotEmpty ? state.userEmail : 'demo@example.com',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            key: const ValueKey('profile.edit'),
            leading: const Icon(Icons.edit),
            title: const Text('Edit Profile'),
            onTap: () => Navigator.of(context).pushNamed('/profile/edit'),
          ),
          ListTile(
            key: const ValueKey('profile.orders'),
            leading: const Icon(Icons.shopping_bag),
            title: const Text('My Orders'),
            onTap: () => Navigator.of(context).pushNamed('/orders'),
          ),
          ListTile(
            key: const ValueKey('profile.logout'),
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () {
              ExampleStateContainer.instance.isLoggedIn = false;
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
    );
  }
}
