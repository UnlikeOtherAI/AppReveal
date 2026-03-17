import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with ScreenIdentifiable {
  bool _notifications = true;
  bool _darkMode = false;
  bool _analytics = true;

  @override
  String get screenKey => 'settings.main';

  @override
  String get screenTitle => 'Settings';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            key: const ValueKey('settings.notifications'),
            title: const Text('Push Notifications'),
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          SwitchListTile(
            key: const ValueKey('settings.dark_mode'),
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: (v) => setState(() => _darkMode = v),
          ),
          SwitchListTile(
            key: const ValueKey('settings.analytics'),
            title: const Text('Analytics'),
            value: _analytics,
            onChanged: (v) => setState(() => _analytics = v),
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('settings.privacy'),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            key: const ValueKey('settings.terms'),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            key: const ValueKey('settings.version'),
            title: const Text('Version'),
            trailing: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}
